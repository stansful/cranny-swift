// CrannyNotes/Model/CoalescingScheduler.swift — "debounced" with a ceiling: the first request starts ONE wait and
// later requests ride along instead of restarting it. Autosave (ARCHITECTURE.md §10.6, 0.5 s) uses it so that a
// `kill -9` loses at most the last 0.5 s of typing (a pure trailing debounce would never save during continuous
// typing); "Automatic" language detection uses it to stay off the keystroke path. One sleeping task at most;
// nothing runs while nothing changed.
import Foundation

@MainActor final class CoalescingScheduler {
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

    /// The action is waiting to run.
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

    /// Runs the action now (a delete, terminate) and forgets the pending wait.
    func fireNow() {
        cancel()
        action()
    }

    func cancel() {
        task?.cancel()
        task = nil
    }
}
