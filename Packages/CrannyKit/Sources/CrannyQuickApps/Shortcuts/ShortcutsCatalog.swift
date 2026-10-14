// CrannyQuickApps/Shortcuts/ShortcutsCatalog.swift — the user's Shortcuts.app shortcuts, read on demand.
//
// Energy: nothing is read at launch. The list is refreshed when someone needs it — the Settings pane appears,
// the add menu opens, the ⌘K palette opens — and only if the last read is older than the caller's limit.
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

    /// Reads the list unless it is younger than `maximumAge` seconds. Concurrent callers share one read.
    func refresh(maximumAge: TimeInterval = 0) async {
        if let inFlight { return await inFlight.value }
        if let loadedAt, now().timeIntervalSince(loadedAt) < maximumAge { return }
        let task = Task { await load() }
        inFlight = task
        await task.value
        inFlight = nil
    }

    private func load() async {
        state = .loading
        do {
            shortcuts = try await cli.list()
            loadedAt = now()
            state = .loaded
        } catch let error as QuickAppsError {
            state = .failed(error)
        } catch {
            state = .failed(.listFailed)
        }
    }
}
