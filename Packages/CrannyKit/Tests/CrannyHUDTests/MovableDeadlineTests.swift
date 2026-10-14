// The hide and announcement sleeper: moving the deadline delays the one action; cancelling drops it.
import Foundation
import Testing
@testable import CrannyHUD

@MainActor @Suite struct MovableDeadlineTests {
    @Test func firesOnceAtTheLatestDeadline() async throws {
        let timer = MovableDeadline(now: { Date() })
        var fired: [Date] = []
        let start = Date()
        timer.schedule(at: start.addingTimeInterval(0.05)) { fired.append(Date()) }
        timer.schedule(at: start.addingTimeInterval(0.2)) { fired.append(Date()) }       // a press moves it
        #expect(timer.isPending)
        #expect(await eventually { fired.count == 1 })
        #expect(fired[0].timeIntervalSince(start) >= 0.19)
        try await Task.sleep(for: .milliseconds(100))
        #expect(fired.count == 1)
        #expect(!timer.isPending)
    }

    @Test func cancelDropsTheAction() async throws {
        let timer = MovableDeadline(now: { Date() })
        var fired = false
        timer.schedule(at: Date().addingTimeInterval(0.05)) { fired = true }
        timer.cancel()
        try await Task.sleep(for: .milliseconds(150))
        #expect(!fired)
        #expect(!timer.isPending)
    }
}
