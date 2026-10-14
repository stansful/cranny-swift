// CrannyTray/Store/TrayStore.swift — the Tray's model (main actor, observable): items, selection, running pipelines,
// the Undo offer. File work happens in `TrayStorage` and `PipelineRunner` off the main actor; this type only
// orchestrates and publishes state (ARCHITECTURE.md §9.1). Pipelines: `TrayStore+Pipelines.swift`; user actions
// (copy, reveal, Quick Look, AirDrop): `TrayStore+Actions.swift`.
import CrannyCore
import Foundation
import Observation
import os

private let log = Log.logger(.tray)

/// The folders the Tray uses. `live(paths:)` in the app; temporary ones in tests and previews.
nonisolated struct TrayDirectories: Sendable, Equatable {
    /// Copies and `index.json`.
    var root: URL
    /// Scratch space for pipeline runs (emptied after each run).
    var work: URL
    /// Files under these are temporary: always copied, never written next to.
    var temporaryRoots: [URL]
    /// Results of tray-owned files.
    var downloads: URL

    /// No I/O: folders are created on first use (ARCHITECTURE.md §3.4, `register` stays cheap).
    static func live(paths: AppPaths) -> TrayDirectories {
        let fm = FileManager.default
        let caches = paths.caches.appending(path: ModuleID.tray.rawValue, directoryHint: .isDirectory)
        let screenshots = fm.homeDirectoryForCurrentUser.appending(path: "Library/Containers/com.apple.screencaptureui",
                                                                   directoryHint: .isDirectory)
        return TrayDirectories(
            root: paths.root.appending(path: ModuleID.tray.rawValue, directoryHint: .isDirectory),
            work: caches.appending(path: "Work", directoryHint: .isDirectory),
            temporaryRoots: [caches, fm.temporaryDirectory, screenshots],
            downloads: fm.urls(for: .downloadsDirectory, in: .userDomainMask).first
                ?? fm.homeDirectoryForCurrentUser.appending(path: "Downloads", directoryHint: .isDirectory))
    }

    /// Everything inside one throw-away folder (tests, previews, Debug QA samples).
    static func temporary(_ base: URL = FileManager.default.temporaryDirectory
        .appending(path: "cranny-tray-\(UUID().uuidString)", directoryHint: .isDirectory)) -> TrayDirectories {
        TrayDirectories(root: base.appending(path: "Tray"), work: base.appending(path: "Work"),
                        temporaryRoots: [base.appending(path: "Incoming")], downloads: base.appending(path: "Downloads"))
    }
}

@MainActor @Observable final class TrayStore {
    // MARK: Observed state

    /// Newest first.
    private(set) var items: [TrayItem] = []
    /// Current location of each item; an item without one is missing (moved or deleted link).
    private(set) var urls: [UUID: URL] = [:]
    private(set) var isLoaded = false
    var selection = TraySelection()
    /// Running pipelines (tiles dim behind a ring) and failed runs of dropped files.
    var jobs: [TrayJob] = []
    /// One line per tile that failed (DESIGN.md §8.2 "Error").
    var failures: [UUID: String] = [:]
    /// Results that just slid in (6-pt accent "new" dot) until the page is left.
    var freshItems: Set<UUID> = []
    /// The 5-s Undo chip after a pipeline wrote files.
    var undoOffer: TrayUndoOffer?

    // MARK: Dependencies

    @ObservationIgnored let settings: SettingsStore
    @ObservationIgnored let notch: any NotchControl
    @ObservationIgnored let haptics: Haptics
    @ObservationIgnored let system: any TraySystem
    @ObservationIgnored let storage: TrayStorage
    @ObservationIgnored let directories: TrayDirectories
    @ObservationIgnored let thumbnails = ThumbnailCache()
    @ObservationIgnored var now: @MainActor () -> Date = { Date() }
    @ObservationIgnored private let index: JSONFileStore<TrayIndex>
    @ObservationIgnored private let saver = Debouncer(delay: .milliseconds(300))
    @ObservationIgnored private var hasUnsavedChanges = false
    @ObservationIgnored private var loading: Task<Void, Never>?
    @ObservationIgnored private var expiryTask: Task<Void, Never>?
    @ObservationIgnored private var retentionToken: ObservationToken?
    @ObservationIgnored var tasks: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored var undoTask: Task<Void, Never>?
    @ObservationIgnored var lastAnnouncement: Date?

    init(settings: SettingsStore, notch: any NotchControl, haptics: Haptics, system: any TraySystem,
         directories: TrayDirectories) {
        self.settings = settings; self.notch = notch; self.haptics = haptics; self.system = system
        self.directories = directories
        storage = TrayStorage(root: directories.root, temporaryRoots: directories.temporaryRoots)
        index = JSONFileStore(url: directories.root.appending(path: "index.json"), defaultValue: TrayIndex())
    }

    // MARK: Derived

    var placement: OutputPlacement {
        OutputPlacement(trayRoot: directories.root, temporaryRoots: directories.temporaryRoots, downloads: directories.downloads)
    }
    var order: [UUID] { items.map(\.id) }
    var totalSize: Int64 { items.reduce(0) { $0 + $1.size } }
    func item(_ id: UUID) -> TrayItem? { items.first { $0.id == id } }
    func url(_ id: UUID) -> URL? { urls[id] }
    /// The selected items in tray order.
    var selectedItems: [TrayItem] { items.filter { selection.contains($0.id) } }
    func job(for id: UUID) -> TrayJob? { jobs.first { $0.sourceIDs.contains(id) && $0.failure == nil } }

    // MARK: Loading

    /// Reads the index once (launch hook); applies Clear on quit (after a crash) and the one-day expiry.
    func load() async {
        if let loading { return await loading.value }
        let task = Task { await self.performLoad() }
        loading = task
        await task.value
    }

    private func performLoad() async {
        var loaded = await index.load().items
        let policy = settings[TraySettings.retention]
        var gone = Retention.expired(loaded, policy: policy, now: now())
        if Retention.clearsOnQuit(policy) { gone = Set(loaded.map(\.id)) }
        if !gone.isEmpty {
            await storage.deleteOwned(loaded.filter { gone.contains($0.id) })
            loaded.removeAll { gone.contains($0.id) }
            hasUnsavedChanges = true
        }
        let resolved = await storage.resolve(loaded)
        for fresh in resolved.refreshed {
            if let i = loaded.firstIndex(where: { $0.id == fresh.id }) { loaded[i] = fresh; hasUnsavedChanges = true }
        }
        items = loaded
        urls = resolved.urls
        isLoaded = true
        if hasUnsavedChanges { persist() }
        await storage.removeOrphans(keeping: loaded)
        scheduleExpiry()
        retentionToken = observe({ [weak self] in self?.settings[TraySettings.retention] }) { [weak self] _ in
            self?.applyRetention()
        }
        log.info("tray loaded: \(loaded.count, privacy: .public) item(s)")
    }

    /// Replaces the items without touching disk (previews and tests).
    func setContent(_ newItems: [TrayItem], urls newURLs: [UUID: URL]) {
        items = newItems
        urls = newURLs
        isLoaded = true
        loading = Task {}
    }

    /// Re-checks where linked files are (the Tray page appears); stale bookmarks are refreshed.
    func refreshLocations() async {
        guard isLoaded else { return }
        let snapshot = items
        let resolved = await storage.resolve(snapshot)
        urls = resolved.urls
        for fresh in resolved.refreshed {
            if let i = items.firstIndex(where: { $0.id == fresh.id }) { items[i] = fresh }
        }
        if !resolved.refreshed.isEmpty { persist() }
    }

    // MARK: Adding

    /// Keeps `urls` (copies by default). A file already in the Tray moves to the front instead of being kept twice.
    /// Returns false only when nothing could be kept.
    @discardableResult
    func keep(_ incoming: [URL], opensTray: Bool = true) async -> Bool {
        guard !incoming.isEmpty else { return false }
        await load()
        var existing: [UUID] = []
        var fresh: [URL] = []
        for url in incoming {
            if let match = TrayDedup.match(url, in: items) { existing.append(match.id) } else { fresh.append(url) }
        }
        let added = await storage.ingest(fresh, mode: settings[TraySettings.storageMode], now: now())
        for item in added {
            urls[item.id] = storage.ownedURL(item) ?? item.linkedURL
        }
        let moved = items.filter { existing.contains($0.id) }
        items.removeAll { existing.contains($0.id) }
        items.insert(contentsOf: added + moved, at: 0)
        enforceCap(keeping: Set(added.map(\.id)))
        persist()
        scheduleExpiry()
        guard !added.isEmpty || !moved.isEmpty else { return false }
        if opensTray && settings[TraySettings.opensTrayOnDrop] { notch.open(page: .tray, focus: nil, reason: .drag) }
        return true
    }

    /// Inserts already-made items (pipeline results) after `anchor`, or at the front.
    func insert(_ newItems: [TrayItem], urls newURLs: [UUID: URL], after anchor: UUID?) {
        let position = anchor.flatMap { id in items.firstIndex { $0.id == id } }.map { $0 + 1 } ?? 0
        items.insert(contentsOf: newItems, at: position)
        urls.merge(newURLs) { _, new in new }
        enforceCap(keeping: Set(newItems.map(\.id)))
        persist()
        scheduleExpiry()
    }

    // MARK: Removing

    /// Removes items (owned copies are deleted; linked files are never touched).
    func remove(_ ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        let removed = items.filter { ids.contains($0.id) }
        for job in jobs where job.sourceIDs.contains(where: ids.contains) { tasks[job.id]?.cancel() }
        items.removeAll { ids.contains($0.id) }
        for id in ids { urls[id] = nil; failures[id] = nil; freshItems.remove(id) }
        selection.prune(to: order)
        if let offer = undoOffer, offer.itemIDs.allSatisfy(ids.contains) { undoOffer = nil }
        let storage = storage
        Task { await storage.deleteOwned(removed) }
        persist()
        scheduleExpiry()
    }

    /// Clear (⌥⌘⌫, ⌘K "Clear tray").
    func clear() {
        remove(Set(order))
        jobs.removeAll { $0.failure != nil }
        thumbnails.removeAll()
    }

    /// Items moved or deleted by the receiver of a drag-out (`.move`, Trash) leave the Tray.
    func removeIfGone(_ ids: [UUID]) async {
        let candidates = ids.compactMap { id in urls[id].map { (id, $0) } }
        let gone = await Self.missing(candidates)
        remove(gone)
    }

    @concurrent private static func missing(_ candidates: [(UUID, URL)]) async -> Set<UUID> {
        Set(candidates.filter { !FileManager.default.fileExists(atPath: $0.1.path) }.map(\.0))
    }

    private func enforceCap(keeping: Set<UUID>) {
        let overflow = Retention.overflow(items, maxItems: settings[TraySettings.maxItems], keeping: keeping)
        if !overflow.isEmpty { remove(overflow) }
    }

    // MARK: Retention

    private func applyRetention() {
        let expired = Retention.expired(items, policy: settings[TraySettings.retention], now: now())
        remove(expired)
        scheduleExpiry()
    }

    /// One sleep to the next expiry; no polling (ARCHITECTURE.md §9.2).
    private func scheduleExpiry() {
        expiryTask?.cancel()
        guard let next = Retention.nextExpiry(items, policy: settings[TraySettings.retention]) else { return }
        let delay = max(next.timeIntervalSince(now()), 0)
        expiryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.applyRetention()
        }
    }

    // MARK: Persistence

    /// Saves the index shortly after a change (coalesced).
    func persist() {
        hasUnsavedChanges = true
        saver.schedule { [weak self] in await self?.saveNow() }
    }

    func saveNow() async {
        guard hasUnsavedChanges else { return }
        hasUnsavedChanges = false
        do { try await index.save(TrayIndex(items: items)) } catch {
            hasUnsavedChanges = true
            log.error("could not save the tray index: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// `applicationWillTerminate`: Clear on quit, flush the index, stop running pipelines. Synchronous and quick.
    func terminate() {
        for task in tasks.values { task.cancel() }
        saver.cancel()
        if Retention.clearsOnQuit(settings[TraySettings.retention]) {
            storage.deleteOwnedNow(items)
            items = []
            storage.writeIndexNow(TrayIndex())
        } else if hasUnsavedChanges {
            storage.writeIndexNow(TrayIndex(items: items))
        }
        hasUnsavedChanges = false
        try? FileManager.default.removeItem(at: directories.work)
    }
}

/// Matching a dropped file against the Tray (no duplicates).
nonisolated enum TrayDedup {
    /// The item that already holds `url` (by its original path or link path).
    static func match(_ url: URL, in items: [TrayItem]) -> TrayItem? {
        let path = url.standardizedFileURL.path
        return items.first { item in
            if item.originalPath == path { return true }
            if case .linked(_, let linked) = item.location { return linked == path }
            return false
        }
    }
}
