// `withDeadline`: the result or error of a prompt operation, a time limit that does not wait for a stuck one,
// and the caller's cancellation reaching the operation.
import Foundation
import Testing
@testable import CrannyQuickApps

@Test func deadlinePassesThroughResultsAndErrors() async throws {
    #expect(try await withDeadline(.seconds(5)) { 42 } == 42)
    await #expect(throws: QuickAppsError.listFailed) {
        try await withDeadline(.seconds(5)) { () async throws -> Int in throw QuickAppsError.listFailed }
    }
}

@Test func deadlineAnswersWithoutWaitingForAStuckOperation() async {
    let gate = Gate()
    defer { gate.open() }
    await #expect(throws: DeadlineExceeded.self) {
        try await withDeadline(.milliseconds(100)) { await gate.wait(); return 1 }
    }
    #expect(!gate.isOpen)                                          // answered while the operation was still stuck
    #expect(await waitUntil { gate.sawCancellation })              // the operation was told to stop
}

@Test func cancellingTheCallerAnswersAtOnceAndCancelsTheOperation() async {
    let gate = Gate()
    defer { gate.open() }
    let task = Task { try await withDeadline(.seconds(30)) { await gate.wait(); return 1 } }
    try? await Task.sleep(for: .milliseconds(50))
    task.cancel()
    await #expect(throws: CancellationError.self) { try await task.value }
    #expect(!gate.isOpen)
    #expect(await waitUntil { gate.sawCancellation })
}

@Test func anAlreadyCancelledCallerNeverStartsTheOperation() async {
    let runs = Counter()
    let task = Task {
        withUnsafeCurrentTask { $0?.cancel() }
        return try await withDeadline(.seconds(5)) { runs.next() }
    }
    await #expect(throws: CancellationError.self) { try await task.value }
    try? await Task.sleep(for: .milliseconds(50))
    #expect(runs.count == 0)
}
