import Foundation
import Observation
import Testing
@testable import CrannyCore

@MainActor @Observable private final class Source {
    var value = 0
    var unrelated = 0
}

@MainActor private final class Probe {
    var evaluations = 0
    var delivered: [Int] = []
}

/// Lets the observer's follow-up task run (it hops back to the main actor after a change).
@MainActor private func settle(until condition: () -> Bool) async {
    for _ in 0..<200 where !condition() { await Task.yield() }
}

@MainActor @Suite("observe(_:onChange:)") struct ObservationTests {
    @Test func evaluatesTheValueOncePerRegistrationAndPerChange() async {
        let source = Source(), probe = Probe()
        let token = observe({ probe.evaluations += 1; return source.value }, onChange: { probe.delivered.append($0) })
        #expect(probe.evaluations == 1)                     // one pass reads and registers

        source.value = 1
        await settle { !probe.delivered.isEmpty }
        #expect(probe.delivered == [1])
        #expect(probe.evaluations == 2)                     // one pass per change, not two

        source.value = 2
        await settle { probe.delivered.count == 2 }
        #expect(probe.delivered == [1, 2] && probe.evaluations == 3)
        withExtendedLifetime(token) {}
    }

    @Test func deliversOnlyRealChangesAndStopsWhenCancelled() async {
        let source = Source(), probe = Probe()
        let token = observe({ probe.evaluations += 1; return source.value }, onChange: { probe.delivered.append($0) })
        source.value = 0                                    // the same value: nothing is delivered
        await settle { false }
        #expect(probe.delivered.isEmpty)
        let evaluations = probe.evaluations
        source.unrelated = 5                                // not read by the closure: not even evaluated
        await settle { false }
        #expect(probe.evaluations == evaluations)

        token.cancel()
        source.value = 3
        await settle { false }
        #expect(probe.delivered.isEmpty)
    }
}

@MainActor @Suite("Announcer") struct AnnouncerTests {
    private final class Clock { var time: TimeInterval = 1000 }

    @Test func alertsAndResultsShareOneLimitFeedbackIsNeverLimited() {
        let clock = Clock()
        var posted: [String] = []
        let announcer = Announcer(post: { posted.append($0) }, now: { clock.time })
        #expect(announcer.announce("Timer done", kind: .alert))
        clock.time += 3
        #expect(!announcer.announce("Compress finished", kind: .result))     // another module, same 10-s window
        #expect(announcer.announce("Moved to column 2", kind: .feedback))     // the user's own action: always
        clock.time += 6.9
        #expect(!announcer.announce("Morning routine finished", kind: .result))
        clock.time += 0.1                                                     // 10 s after the alert
        #expect(announcer.announce("Meeting in 1 minute", kind: .alert))
        #expect(!announcer.announce("", kind: .feedback))
        #expect(posted == ["Timer done", "Moved to column 2", "Meeting in 1 minute"])
        #expect(Announcer.interval == 10)
    }

    @Test func servicesShareOneAnnouncer() {
        let services = CrannyServices.preview()
        var posted: [String] = []
        services.announcer = Announcer(post: { posted.append($0) })
        services.announcer.announce("a", kind: .alert)
        services.announcer.announce("b", kind: .result)
        #expect(posted == ["a"])
    }
}
