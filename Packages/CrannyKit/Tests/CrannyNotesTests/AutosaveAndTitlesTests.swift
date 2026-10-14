// AutosaveScheduler with a hand-driven clock ("autosave 0.5 s", bounded loss), title rules and line numbering.
import Foundation
import os
import Testing
@testable import CrannyNotes

/// A sleep that returns only when the test says so.
private final class ManualClock: Sendable {
    private let state = OSAllocatedUnfairLock(initialState: (waiting: [CheckedContinuation<Void, any Error>](), requested: [Duration]()))

    var requested: [Duration] { state.withLock { $0.requested } }

    @Sendable func sleep(_ duration: Duration) async throws {
        try await withCheckedThrowingContinuation { continuation in
            state.withLock { $0.waiting.append(continuation); $0.requested.append(duration) }
        }
    }

    func advance() {
        let waiting = state.withLock { s -> [CheckedContinuation<Void, any Error>] in
            defer { s.waiting = [] }
            return s.waiting
        }
        for continuation in waiting { continuation.resume() }
    }
}

@Suite("Autosave") struct AutosaveTests {
    private func settle(until condition: () -> Bool) async {
        for _ in 0..<1_000 where !condition() { await Task.yield() }
    }

    @Test func oneWaitPerBurstThenOneSave() async {
        let clock = ManualClock()
        var saves = 0
        let scheduler = AutosaveScheduler(sleep: clock.sleep) { saves += 1 }
        scheduler.schedule()
        scheduler.schedule()                                                    // typing on: no restart
        scheduler.schedule()
        await settle { clock.requested.count == 1 }
        #expect(clock.requested == [.milliseconds(500)])
        #expect(scheduler.isPending)
        clock.advance()
        await settle { saves == 1 }
        #expect(saves == 1)
        #expect(!scheduler.isPending)
        scheduler.schedule()                                                    // the next burst waits again
        await settle { clock.requested.count == 2 }
        #expect(clock.requested.count == 2)
    }

    @Test func fireNowSavesAtOnceAndDropsTheWait() async {
        let clock = ManualClock()
        var saves = 0
        let scheduler = AutosaveScheduler(sleep: clock.sleep) { saves += 1 }
        scheduler.schedule()
        await settle { clock.requested.count == 1 }
        scheduler.fireNow()
        #expect(saves == 1)
        #expect(!scheduler.isPending)
        clock.advance()                                                         // the old wait ends: no second save
        for _ in 0..<100 { await Task.yield() }
        #expect(saves == 1)
    }
}

@Suite("Titles and line numbers") struct TitlesTests {
    @Test func uniqueNames() {
        let make: (Int?) -> String = { $0.map { "Untitled \($0)" } ?? "Untitled" }
        #expect(NoteTitles.unique(existing: [], make: make) == "Untitled")
        #expect(NoteTitles.unique(existing: ["Untitled"], make: make) == "Untitled 2")
        #expect(NoteTitles.unique(existing: ["Untitled", "Untitled 2", "Untitled 4"], make: make) == "Untitled 3")
    }

    @Test func derivedTitles() {
        #expect(NoteTitles.derived(from: "\n\n## Release notes\nbody") == "Release notes")
        #expect(NoteTitles.derived(from: "- [ ] milk") == "[ ] milk")
        #expect(NoteTitles.derived(from: "   \n\t") == nil)
        let long = NoteTitles.derived(from: String(repeating: "a", count: 100))
        #expect(long?.count == NoteTitles.derivedLength)
        #expect(long?.hasSuffix("…") == true)
    }

    @Test func lineStartsAndNumbers() {
        #expect(LineNumberRuler.lineStarts(in: "") == [0])
        #expect(LineNumberRuler.lineStarts(in: "a\nb\n") == [0, 2, 4])
        #expect(LineNumberRuler.lineStarts(in: "a\r\nb\rc") == [0, 3, 5])         // CRLF counts once
        let starts = LineNumberRuler.lineStarts(in: "one\ntwo\nthree")
        #expect(LineNumberRuler.lineNumber(at: 0, lineStarts: starts) == 1)
        #expect(LineNumberRuler.lineNumber(at: 3, lineStarts: starts) == 1)
        #expect(LineNumberRuler.lineNumber(at: 4, lineStarts: starts) == 2)
        #expect(LineNumberRuler.lineNumber(at: 13, lineStarts: starts) == 3)
    }
}
