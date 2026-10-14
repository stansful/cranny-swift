// CrannyHUD/Model/MovableDeadline.swift — one sleeping task per deadline that later calls only move
// (ARCHITECTURE.md §9.1 rule 7: `Task.sleep` to deadlines, never repeating timers). Key repeat arrives at ~30 Hz;
// rescheduling a task per press would churn, so a press just moves the date and the sleeper re-checks it.
import Foundation

@MainActor final class MovableDeadline {
    private let now: @MainActor () -> Date
    private var deadline: Date?
    private var action: (@MainActor () -> Void)?
    private var task: Task<Void, Never>?

    /// `now` is the clock the deadline is measured against (sleeps use real time).
    init(now: @escaping @MainActor () -> Date) { self.now = now }

    var isPending: Bool { task != nil }

    /// Runs the latest `action` once, at the latest `deadline` (a later call moves both).
    func schedule(at deadline: Date, _ action: @escaping @MainActor () -> Void) {
        self.deadline = deadline
        self.action = action
        guard task == nil else { return }
        task = Task { [weak self] in
            while let wait = self?.secondsLeft(), wait > 0 {
                try? await Task.sleep(for: .seconds(wait))
                if Task.isCancelled { return }
            }
            guard let self, !Task.isCancelled else { return }
            let action = self.action
            self.task = nil
            self.deadline = nil
            self.action = nil
            action?()
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        deadline = nil
        action = nil
    }

    private func secondsLeft() -> TimeInterval? { deadline.map { $0.timeIntervalSince(now()) } }
}
