// CrannyQuickApps/Shortcuts/ShortcutRuns.swift — running shortcuts and the state each tile shows
// (DESIGN.md §7.3: progress ring while running, a check on success, a danger badge on failure).
//
// One `Task` per running shortcut, stored here and cancelled on stop (which terminates the process) and on quit.
// Results reset with one `Task.sleep` each (no timers): success after `successHold`, failure after `failureHold`.
import CrannyCore
import Foundation
import Observation

/// What a shortcut tile shows.
nonisolated enum ShortcutRunState: Equatable, Sendable {
    case idle
    case running(since: Date)
    case succeeded
    case failed(QuickAppsError)

    var isRunning: Bool { if case .running = self { true } else { false } }
}

/// How a run ended.
nonisolated enum ShortcutRunOutcome: Equatable, Sendable {
    case succeeded
    case failed(QuickAppsError)
    /// Stopped by the user or by quitting Cranny: no badge.
    case cancelled
}

@MainActor @Observable final class ShortcutRuns {
    private(set) var states: [String: ShortcutRunState] = [:]

    @ObservationIgnored private let cli: ShortcutsCLI
    @ObservationIgnored private let successHold: Duration
    @ObservationIgnored private let failureHold: Duration
    @ObservationIgnored private var runs: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var resets: [String: Task<Void, Never>] = [:]

    init(cli: ShortcutsCLI, successHold: Duration = .seconds(1.6), failureHold: Duration = .seconds(60)) {
        self.cli = cli; self.successHold = successHold; self.failureHold = failureHold
    }

    func state(of id: String) -> ShortcutRunState { states[id] ?? .idle }
    func isRunning(_ id: String) -> Bool { state(of: id).isRunning }
    var hasRunningShortcuts: Bool { states.values.contains { $0.isRunning } }

    /// Starts the shortcut unless it is already running. `onFinish` runs on the main actor after the state changed.
    @discardableResult
    func start(_ id: String, onFinish: @escaping @MainActor (ShortcutRunOutcome) -> Void = { _ in }) -> Bool {
        guard !isRunning(id) else { return false }
        resets[id]?.cancel()
        resets[id] = nil
        states[id] = .running(since: Date())
        runs[id] = Task { [cli] in
            let outcome: ShortcutRunOutcome
            do {
                try await cli.run(id)
                outcome = .succeeded
            } catch is CancellationError {
                outcome = .cancelled
            } catch let error as QuickAppsError {
                outcome = .failed(error)
            } catch {
                outcome = .failed(.shortcutFailed)
            }
            finish(id, outcome)
            onFinish(outcome)
        }
        return true
    }

    /// Stops a running shortcut (terminates its process). No badge follows.
    func cancel(_ id: String) { runs[id]?.cancel() }

    /// Quit: stop every run and forget every badge.
    func cancelAll() {
        for task in runs.values { task.cancel() }
        for task in resets.values { task.cancel() }
        resets = [:]
    }

    /// Replaces the outcome of a failed run (the model learns a shortcut was deleted only after re-reading the list).
    func replaceFailure(of id: String, with error: QuickAppsError) {
        if case .failed = state(of: id) { states[id] = .failed(error) }
    }

    /// Previews, snapshots and QA: shows a state without running anything.
    func show(_ state: ShortcutRunState, for id: String) { states[id] = state }

    private func finish(_ id: String, _ outcome: ShortcutRunOutcome) {
        runs[id] = nil
        switch outcome {
        case .cancelled:
            states[id] = nil
        case .succeeded:
            states[id] = .succeeded
            scheduleReset(id, after: successHold)
        case .failed(let error):
            states[id] = .failed(error)
            scheduleReset(id, after: failureHold)
        }
    }

    private func scheduleReset(_ id: String, after delay: Duration) {
        resets[id]?.cancel()
        resets[id] = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            if !self.isRunning(id) { self.states[id] = nil }
            self.resets[id] = nil
        }
    }
}
