// CrannyQuickApps/Shortcuts/ShortcutsCatalog.swift — the user's Shortcuts.app shortcuts, read on demand.
//
// Energy: nothing is read at launch. The list is refreshed when someone needs it — the Settings pane appears,
// the add menu opens, the ⌘K palette opens — and only if the last read is older than the caller's limit.
// A read is bounded by the CLI's `listTimeout`: a stuck `shortcuts list` ends as `.failed`, and the next caller
// reads again instead of waiting behind it.
import CrannyCore
import Foundation
import Observation

@MainActor @Observable final class ShortcutsCatalog {
    enum State: Equatable {
        case idle, loading, loaded
        case failed(QuickAppsError)
    }

    /// The last list read (kept while a refresh runs or after it failed).
    private(set) var shortcuts: [ShortcutInfo] = []
    private(set) var state: State = .idle
    /// `ShortcutEntry.displayName` of each listed shortcut by id, worked out once per read (⌘K matches on every
    /// keystroke). Always set together with `shortcuts`.
    @ObservationIgnored private var displayNames: [String: String] = [:]

    @ObservationIgnored private let cli: ShortcutsCLI
    @ObservationIgnored private let now: @MainActor () -> Date
    @ObservationIgnored private var loadedAt: Date?
    @ObservationIgnored private var inFlight: Task<Void, Never>?

    init(cli: ShortcutsCLI, now: @escaping @MainActor () -> Date = { Date() }) {
        self.cli = cli; self.now = now
    }

    /// Whether the list has been read successfully at least once (only then "missing" means deleted).
    var hasLoaded: Bool { loadedAt != nil }

    /// Name of a shortcut in the last list, nil if it is not there (or the list was never read).
    func info(for id: String) -> ShortcutInfo? { shortcuts.first { $0.id == id } }

    /// What a listed shortcut is called on screen (`ShortcutEntry.displayName`), without working it out again.
    func displayName(of info: ShortcutInfo) -> String {
        displayNames[info.id] ?? ShortcutEntry.displayName(for: info.name)
    }

    /// Reads the list unless the last read succeeded less than `maximumAge` seconds ago (after a failure it always
    /// reads again). Concurrent callers share one read.
    func refresh(maximumAge: TimeInterval = 0) async {
        if let inFlight { return await inFlight.value }
        if state == .loaded, let loadedAt, now().timeIntervalSince(loadedAt) < maximumAge { return }
        let task = Task { await load() }
        inFlight = task
        await task.value
        inFlight = nil
    }

    /// Stops a read in progress (the module stops): the CLI is interrupted, the state and the last list are kept.
    func cancel() {
        inFlight?.cancel()
    }

    private func load() async {
        let previous = state
        state = .loading
        do {
            let list = try await cli.list()
            displayNames = Dictionary(list.map { ($0.id, ShortcutEntry.displayName(for: $0.name)) },
                                      uniquingKeysWith: { first, _ in first })
            shortcuts = list
            loadedAt = now()
            state = .loaded
        } catch is CancellationError {
            state = previous
        } catch let error as QuickAppsError {
            state = .failed(error)
        } catch {
            state = .failed(.listFailed)
        }
    }
}
