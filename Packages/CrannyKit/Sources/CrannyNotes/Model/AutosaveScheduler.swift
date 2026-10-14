// CrannyNotes/Model/AutosaveScheduler.swift — "autosave debounced 0.5 s" with a ceiling (ARCHITECTURE.md §10.6):
// the first change after a save starts ONE 0.5-s wait and later changes ride along instead of restarting it.
// A pure trailing debounce would never save during continuous typing; this bounds what a `kill -9` can lose
// to the last 0.5 s of typing. One sleeping task at most; nothing runs while nothing changed.
import Foundation

@MainActor final class AutosaveScheduler {
    typealias Sleep = @Sendable (Duration) async throws -> Void

    private let delay: Duration
    private let sleep: Sleep
    private let action: @MainActor () -> Void
    private var task: Task<Void, Never>?

    /// `sleep` is injectable so tests drive the clock.
    init(delay: Duration = .milliseconds(500), sleep: @escaping Sleep = { try await Task.sleep(for: $0) },
         action: @escaping @MainActor () -> Void) {
        self.delay = delay; self.sleep = sleep; self.action = action
    }

    /// A save is waiting.
    var isPending: Bool { task != nil }

    /// Starts the wait unless one is already running.
    func schedule() {
        guard task == nil else { return }
        task = Task { [weak self, delay, sleep] in
            do { try await sleep(delay) } catch { return }
            guard !Task.isCancelled, let self else { return }
            self.task = nil
            self.action()
        }
    }

    /// Runs the action now (terminate, note switch) and forgets the pending wait.
    func fireNow() {
        cancel()
        action()
    }

    func cancel() {
        task?.cancel()
        task = nil
    }
}
