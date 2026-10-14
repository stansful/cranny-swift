// CrannyQuickApps/Shortcuts/Deadline.swift — a time limit for one CLI call that a stuck call cannot outlast.
//
// A task group waits for its cancelled children, so a tool that never exits would still hold the caller. Here the
// operation runs in a task of its own: when the limit passes it is cancelled (for `ProcessRunner`: SIGINT, then
// SIGTERM after the grace) and the caller is answered at once, whether or not the operation has stopped yet.
import Foundation
import os

/// The operation did not finish within its time limit.
nonisolated struct DeadlineExceeded: Error, Equatable {}

/// Returns what `operation` returns, or throws `DeadlineExceeded` once `limit` has passed, and then cancels the
/// operation without waiting for it. Cancelling the caller cancels the operation and throws `CancellationError`.
nonisolated func withDeadline<T: Sendable>(_ limit: Duration,
                                           _ operation: @escaping @Sendable () async throws -> T) async throws -> T {
    let race = DeadlineRace<T>()
    return try await withTaskCancellationHandler {
        try await withCheckedThrowingContinuation { continuation in
            race.start(continuation, limit: limit, operation: operation)
        }
    } onCancel: {
        race.finish(.failure(CancellationError()))
    }
}

/// The operation, the timer and the caller's cancellation race; the first to finish answers the caller exactly
/// once and cancels the others.
private nonisolated final class DeadlineRace<T: Sendable>: Sendable {
    private nonisolated struct State: Sendable {
        var continuation: CheckedContinuation<T, any Error>?
        var outcome: Result<T, any Error>?
        var tasks: [Task<Void, Never>] = []
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    func start(_ continuation: CheckedContinuation<T, any Error>, limit: Duration,
               operation: @escaping @Sendable () async throws -> T) {
        // The caller was cancelled before this ran: answer now and start nothing.
        let early = state.withLock { state -> Result<T, any Error>? in
            if state.outcome == nil { state.continuation = continuation }
            return state.outcome
        }
        if let early { continuation.resume(with: early); return }

        let work = Task { [self] in
            do { finish(.success(try await operation())) } catch { finish(.failure(error)) }
        }
        let timer = Task { [self] in
            guard (try? await Task.sleep(for: limit)) != nil else { return }   // cancelled: someone else won
            finish(.failure(DeadlineExceeded()))
        }
        // Something may have finished while the tasks were being created: then nobody else will cancel them.
        let finished = state.withLock { state -> Bool in
            if state.outcome == nil { state.tasks = [work, timer] }
            return state.outcome != nil
        }
        if finished { work.cancel(); timer.cancel() }
    }

    /// The first call wins: it answers the caller and cancels whatever still runs. Later calls do nothing.
    func finish(_ outcome: Result<T, any Error>) {
        let (continuation, tasks) = state.withLock { state -> (CheckedContinuation<T, any Error>?, [Task<Void, Never>]) in
            guard state.outcome == nil else { return (nil, []) }
            state.outcome = outcome
            defer { state.continuation = nil; state.tasks = [] }
            return (state.continuation, state.tasks)
        }
        for task in tasks { task.cancel() }
        continuation?.resume(with: outcome)
    }
}
