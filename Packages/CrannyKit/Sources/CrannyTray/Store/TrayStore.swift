// CrannyTray/Store/TrayStore.swift — the Tray's model (main actor, observable): items, selection, running pipelines,
// the Undo offer. File work happens in `TrayStorage` and `PipelineRunner` off the main actor; this type only
// orchestrates and publishes state (ARCHITECTURE.md §9.1). Pipelines: `TrayStore+Pipelines.swift`; user actions
// (copy, reveal, Quick Look, AirDrop): `TrayStore+Actions.swift`. Folders: `TrayDirectories.swift`.
import CrannyCore
import Foundation
import Observation
import os

private let log = Log.logger(.tray)

@MainActor @Observable final class TrayStore {
    // MARK: Observed state

    /// Newest first.
    private(set) var items: [TrayItem] = []
    /// Current location of each item; an item without one is missing (moved or deleted link).
    private(set) var urls: [UUID: URL] = [:]
    private(set) var isLoaded = false
    var selection = TraySelection()
    /// Running pipelines (tiles dim behind a ring), failed runs of dropped files and files that could not be kept.
    var jobs: [TrayJob] = []
    /// One line per tile that failed (DESIGN.md §8.2 "Error").
    var failures: [UUID: String] = [:]
    /// Results that just slid in (6-pt accent "new" dot) until the page is left.
    var freshItems: Set<UUID> = []
    /// The 5-s Undo chip after a pipeline wrote files.
    var undoOffer: TrayUndoOffer?
    /// The Tray page is on screen (errors are shown there; the page is opened for them otherwise).
    private(set) var isPageVisible = false

    // MARK: Dependencies

    @ObservationIgnored let settings: SettingsStore
    @ObservationIgnored let notch: any NotchControl
    @ObservationIgnored let haptics: Haptics
    @ObservationIgnored let system: any TraySystem
    @ObservationIgnored let storage: TrayStorage
    @ObservationIgnored let directories: TrayDirectories
    @ObservationIgnored let thumbnails = ThumbnailCache()
    @ObservationIgnored var now: @MainActor () -> Date = { Date() }
    @ObservationIgnored private let saver = Debouncer(delay: .milliseconds(300))
    /// Bumped by every change to the index; `savedRevision` is the newest one known to be on disk. A save is
    /// counted only once its write finished, so the terminate hook also writes while a background save is in flight
    /// (`TrayIndexFile` drops that save if it lands afterwards).
    @ObservationIgnored private var revision = 0
    @ObservationIgnored private var savedRevision = 0
    /// Writes `index.json` off the main actor (tests put a slow writer here). Reads go through
    /// `TrayStorage.readIndex`, which tells a damaged index from a missing one.
    @ObservationIgnored var writeIndex: @Sendable (TrayIndex, _ revision: Int) async throws -> Bool
    @ObservationIgnored private var loading: Task<Void, Never>?
    @ObservationIgnored private var expiryTask: Task<Void, Never>?
    @ObservationIgnored private var settingTokens: [ObservationToken] = []
    @ObservationIgnored var tasks: [UUID: Task<Void, Never>] = [:]
    /// The live fraction of each running job (`progress(of:)`): a tick changes one box, so only the views that show
    /// that job's ring re-render, never every tile through `jobs` (`TrayStore+Pipelines.swift`).
    @ObservationIgnored var liveProgress: [UUID: TrayJobProgress] = [:]
    @ObservationIgnored var undoTask: Task<Void, Never>?

    init(settings: SettingsStore, notch: any NotchControl, haptics: Haptics, system: any TraySystem,
         directories: TrayDirectories) {
        self.settings = settings; self.notch = notch; self.haptics = haptics; self.system = system
        self.directories = directories
        let storage = TrayStorage(root: directories.root, temporaryRoots: directories.temporaryRoots)
        self.storage = storage
        let file = storage.indexFile
        writeIndex = { index, revision in try await file.writeInBackground(index, revision: revision) }
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
        let read = await storage.readIndex()
        var loaded: [TrayItem]
        var changed = false
        if case .loaded(let index) = read {
            loaded = index.items
        } else {
            // No usable index: the copies are found again from their folders, never deleted for want of an index.
            loaded = await storage.recoverCopies(now: now())
            if !loaded.isEmpty {
                changed = true
                log.info("tray index rebuilt: \(loaded.count, privacy: .public) kept copies found")
            }
        }
        let policy = settings[TraySettings.retention]
        var gone = Retention.expired(loaded, policy: policy, now: now())
        if Retention.clearsOnQuit(policy) { gone = Set(loaded.map(\.id)) }
        if !gone.isEmpty {
            await storage.deleteOwned(loaded.filter { gone.contains($0.id) })
            loaded.removeAll { gone.contains($0.id) }
            changed = true
        }
        let resolved = await storage.resolve(loaded)
        for fresh in resolved.refreshed {
            if let i = loaded.firstIndex(where: { $0.id == fresh.id }) { loaded[i] = fresh; changed = true }
        }
        items = loaded
        urls = resolved.urls
        isLoaded = true
        if changed { persist() }
        if case .loaded = read { await storage.removeOrphans(keeping: loaded) }
        enforceCap(keeping: [])
        scheduleExpiry()
        settingTokens = [
            observe({ [weak self] in self?.settings[TraySettings.retention] }) { [weak self] _ in self?.applyRetention() },
            // A lower "Keep at most" applies at once, not at the next drop.
            observe({ [weak self] in self?.settings[TraySettings.maxItems] }) { [weak self] _ in self?.enforceCap(keeping: []) },
        ]
        log.info("tray loaded: \(loaded.count, privacy: .public) item(s)")
    }

    /// Replaces the items without touching disk (previews and tests).
    func setContent(_ newItems: [TrayItem], urls newURLs: [UUID: URL]) {
        items = newItems
        urls = newURLs
        isLoaded = true
        loading = Task {}
    }

    /// Re-checks where linked files are (the Tray page appears); stale bookmarks are refreshed. The result is merged:
    /// items added while it resolved keep their URL, and items removed meanwhile do not get one back. Each list is
    /// published once and only when something changed, so a page appearance where nothing moved (the usual case)
    /// invalidates no tile.
    func refreshLocations() async {
        guard isLoaded else { return }
        let snapshot = items
        let resolved = await storage.resolve(snapshot)
        let present = Set(order)
        var nextURLs = urls
        for item in snapshot where present.contains(item.id) { nextURLs[item.id] = resolved.urls[item.id] }
        if nextURLs != urls { urls = nextURLs }
        guard !resolved.refreshed.isEmpty else { return }
        var updated = items
        var changed = false
        for fresh in resolved.refreshed {
            guard let i = updated.firstIndex(where: { $0.id == fresh.id }) else { continue }
            updated[i].location = fresh.location
            updated[i].name = fresh.name
            changed = true
        }
        if changed {
            items = updated
            persist()
        }
    }

    // MARK: Adding

    /// Keeps `urls` (copies by default). A file already in the Tray moves to the front (and counts as just added)
    /// instead of being kept twice, unless the original changed since it was copied: then the copy is replaced.
    /// Files that cannot be kept get an error tile. Returns false only when the drop held nothing to keep.
    @discardableResult
    func keep(_ incoming: [URL], opensTray: Bool = true) async -> Bool {
        guard !incoming.isEmpty else { return false }
        await load()
        let matches = incoming.map { (url: $0, item: TrayDedup.match($0, in: items)) }
        let copies = matches.compactMap { match in match.item.flatMap { $0.isOwned ? (url: match.url, item: $0) : nil } }
        let changed = copies.isEmpty ? [] : await storage.changedOriginals(copies)
        var existing: [UUID] = []
        var fresh: [URL] = []
        var replacing: [URL: UUID] = [:]
        for match in matches {
            if let item = match.item, !changed.contains(item.id) {
                existing.append(item.id)
            } else {
                fresh.append(match.url)
                if let item = match.item { replacing[match.url] = item.id }
            }
        }
        let results = await storage.ingestEach(fresh, mode: settings[TraySettings.storageMode], now: now())
        var added: [TrayItem] = []
        var outdated: Set<UUID> = []
        var failed: [(name: String, error: TrayError)] = []
        for (url, result) in zip(fresh, results) {
            switch result {
            case .success(let item):
                added.append(item)
                urls[item.id] = storage.ownedURL(item) ?? item.linkedURL
                if let old = replacing[url] { outdated.insert(old) }
            case .failure(let error):
                failed.append((url.lastPathComponent, error))
            }
        }
        let time = now()
        var moved = items.filter { existing.contains($0.id) }
        for i in moved.indices { moved[i].addedAt = time }          // retention and the cap count from the new drop
        items.removeAll { existing.contains($0.id) }
        items.insert(contentsOf: added + moved, at: 0)
        if !outdated.isEmpty { remove(outdated) }
        enforceCap(keeping: Set((added + moved).map(\.id)))
        showKeepFailures(failed)
        persist()
        await saveNow()                     // a kept copy is in the index at once: a crash now must not lose it
        scheduleExpiry()
        let kept = !added.isEmpty || !moved.isEmpty
        if (kept && opensTray && settings[TraySettings.opensTrayOnDrop]) || (!failed.isEmpty && !isPageVisible) {
            notch.open(page: .tray, focus: nil, reason: .drag)
        }
        return kept || !failed.isEmpty
    }

    /// An error tile per file that could not be kept (dismissed like a failed drop run), and one announcement.
    private func showKeepFailures(_ failed: [(name: String, error: TrayError)]) {
        guard let first = failed.first else { return }
        let title = String(localized: "Keep in Tray", bundle: .module, comment: "Drag catch state: drop zone that keeps the files")
        for (name, error) in failed {
            jobs.removeAll { $0.pipelineID == Self.keepJobID && $0.placeholderName == name }
            jobs.append(TrayJob(id: UUID(), pipelineID: Self.keepJobID, title: title, sourceIDs: [], placeholderName: name,
                                failure: error.errorDescription))
        }
        announce(first.error.errorDescription ?? title)
    }

    /// `TrayJob.pipelineID` of the error tile of a file that could not be kept.
    static let keepJobID = "tray.keep"

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

    /// Removes items (owned copies are deleted; linked files are never touched). Their thumbnails leave the cache.
    func remove(_ ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        let removed = items.filter { ids.contains($0.id) }
        thumbnails.forget(paths: Set(ids.compactMap { urls[$0]?.path }))
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

    /// Clear (⌥⌘⌫, ⌘K "Clear Tray").
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

    /// The oldest items beyond "Keep at most". Files of the drop being kept never make room for themselves, so one
    /// drop larger than the cap is kept whole; the Tray is back at the cap after the next change.
    private func enforceCap(keeping: Set<UUID>) {
        let overflow = Retention.overflow(items, maxItems: settings[TraySettings.maxItems], keeping: keeping)
        if !overflow.isEmpty { remove(overflow) }
    }

    // MARK: Page

    func pageDidAppear() { isPageVisible = true }

    /// A tile was clicked. The panel becomes key so the row's keys (Space, ⌘C, ⌘⌫, ⌘.) reach the Tray and never the
    /// frontmost app, where ⌘⌫ would trash the user's own selection in Finder. It is key for the selection only, not
    /// for typing: the panel still closes when the pointer leaves, and the close hands key status back (DESIGN.md
    /// §3.6, ARCHITECTURE.md §4.10). Controls without selection focus (previews, test doubles) get the plain request.
    func takeSelectionFocus() {
        if let focus = notch as? any NotchSelectionFocus { focus.requestSelectionFocus() } else { notch.requestKeyboardFocus() }
    }

    /// Leaving the Tray page: "new" dots go, the selection stays.
    func pageDidDisappear() {
        isPageVisible = false
        freshItems = []
    }

    // MARK: Retention

    /// Expires every item due within `Retention.batchWindow`, so drops made within a minute of each other leave
    /// together: one wake-up, one batch of deletions and one index write instead of one each.
    private func applyRetention() {
        let expired = Retention.expired(items, policy: settings[TraySettings.retention],
                                        now: now().addingTimeInterval(Retention.batchWindow))
        remove(expired)
        scheduleExpiry()
    }

    /// One sleep to the next expiry, with the batch window as timer tolerance so the system can coalesce the wake-up;
    /// no polling (ARCHITECTURE.md §9.2).
    private func scheduleExpiry() {
        expiryTask?.cancel()
        guard let next = Retention.nextExpiry(items, policy: settings[TraySettings.retention]) else { return }
        let delay = max(next.timeIntervalSince(now()), 0)
        expiryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay), tolerance: .seconds(Retention.batchWindow))
            guard !Task.isCancelled else { return }
            self?.applyRetention()
        }
    }

    // MARK: Persistence

    /// Saves the index shortly after a change (coalesced).
    func persist() {
        revision += 1
        saver.schedule { [weak self] in await self?.saveNow() }
    }

    /// Writes the current revision off the main actor (no-op when it is on disk already). A failed write is retried
    /// by the next change or at quit.
    func saveNow() async {
        guard revision > savedRevision else { return }
        let target = revision
        do {
            // false: a newer revision was written meanwhile, which covers this one.
            _ = try await writeIndex(TrayIndex(items: items), target)
            savedRevision = max(savedRevision, target)
        } catch {
            log.error("could not save the tray index: \(TrayLogCode.of(error), privacy: .public) \(error.localizedDescription, privacy: .private)")
        }
    }

    /// `applicationWillTerminate`: Clear on quit, flush the index, stop running pipelines. Synchronous and quick.
    /// Writes whenever the newest revision is not known to be on disk, also while a background save is in flight:
    /// that save may not finish before the process exits, and if it does, it is older and is dropped.
    func terminate() {
        for task in tasks.values { task.cancel() }
        saver.cancel()
        if Retention.clearsOnQuit(settings[TraySettings.retention]) {
            storage.deleteOwnedNow(items)
            items = []
            revision += 1
        }
        if revision > savedRevision {
            do {
                try storage.indexFile.write(TrayIndex(items: items), revision: revision)
                savedRevision = revision
            } catch {
                log.error("could not write the tray index: \(TrayLogCode.of(error), privacy: .public) \(error.localizedDescription, privacy: .private)")
            }
        }
        try? FileManager.default.removeItem(at: directories.work)
    }
}
