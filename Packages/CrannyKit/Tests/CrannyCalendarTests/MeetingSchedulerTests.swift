import CrannyCore
import Foundation
import Observation
import Testing
@testable import CrannyCalendar

/// The scheduler: revisions on meaningful changes and ONE pending wake-up at the next boundary — none at all
/// when nothing is upcoming (ARCHITECTURE.md §10.3 "no timer while no event is upcoming").
@Suite @MainActor struct MeetingSchedulerTests {
    private let time = TestTime(T.date(h: 9))
    /// Never returns during a test: wake-ups are observed through `nextWake`, time moves by hand.
    private let parked: @Sendable (Duration) async throws -> Void = { _ in try await Task.sleep(for: .seconds(3600)) }

    private func scheduler(_ events: [EventSnapshot], lead: Int = 5) -> MeetingScheduler {
        MeetingScheduler(events: { events }, leadMinutes: { lead }, clock: time.clock, sleep: parked)
    }

    @Test func noWakeWhenNothingIsUpcoming() {
        let s = scheduler([T.event("done", start: T.date(h: 8), minutes: 30),
                           T.event("holiday", start: T.date(h: 0), minutes: 1440, allDay: true)])
        s.replan()
        #expect(s.nextWake == nil)
        #expect(s.state == .none)
        let empty = scheduler([])
        empty.replan()
        #expect(empty.nextWake == nil)
    }

    @Test func wakesAtEachBoundaryAndBumpsRevisions() {
        let standup = T.event("standup", start: T.date(h: 10), minutes: 15, link: "https://zoom.us/j/1")
        let s = scheduler([standup])
        s.replan()
        #expect(s.nextWake == T.date(h: 9, 55))
        #expect(s.soonRevision == 0 && s.currentRevision == 0)

        time.now = T.date(h: 9, 55)                       // lead time: meeting soon, a P1 alert
        s.replan()
        #expect(s.state.soon?.stage == .lead)
        #expect(s.soonRevision == 1)
        #expect(s.nextWake == T.date(h: 9, 56))           // the alert settles to P2

        time.now = T.date(h: 9, 56)
        s.replan()
        #expect(s.soonRevision == 1)                       // same stage: not a meaningful change
        #expect(s.nextWake == T.date(h: 9, 59))

        time.now = T.date(h: 9, 59)                        // last minute: second revision
        s.replan()
        #expect(s.state.soon?.stage == .lastMinute)
        #expect(s.soonRevision == 2)

        time.now = T.date(h: 10)                           // started
        s.replan()
        #expect(s.state.soon == nil)
        #expect(s.state.current?.id == "standup")
        #expect(s.currentRevision == 1)
        #expect(s.nextWake == T.date(h: 10, 15))

        time.now = T.date(h: 10, 15)
        s.replan()
        #expect(s.state == .none)
        #expect(s.nextWake == nil)                          // nothing ahead: no task
    }

    @Test func eventChangesReplanThroughObservation() async {
        let store = FixtureEventsBox()
        let s = MeetingScheduler(events: { store.events }, leadMinutes: { 5 }, clock: time.clock, sleep: parked)
        s.start()
        #expect(s.nextWake == nil)
        store.events = [T.event("call", start: T.date(h: 9, 30))]
        await settle()
        #expect(s.nextWake == T.date(h: 9, 25))
        s.stop()
        #expect(s.nextWake == nil)
    }

    @Test func samplesNeverSchedule() {
        let s = scheduler([T.event("soon", start: T.date(h: 9, 3))])
        s.replan(scheduling: false)
        #expect(s.state.soon != nil)
        #expect(s.nextWake == nil)
    }

    @Test func wakeUpReplansAfterTheSleep() async throws {
        // A real (short) sleep: the scheduler wakes, re-plans and moves on to the next boundary.
        let event = T.event("soon", start: T.date(h: 9, 5))
        let s = MeetingScheduler(events: { [event] }, leadMinutes: { 5 }, clock: time.clock,
                                 sleep: { _ in try await Task.sleep(for: .milliseconds(5)) })
        time.now = T.date(h: 8, 59, s: 59)
        s.replan()
        #expect(s.nextWake == T.date(h: 9))
        time.now = T.date(h: 9)
        await settle()
        #expect(s.soonRevision == 1)
        #expect(s.nextWake == T.date(h: 9, 1))
        s.stop()
    }
}

/// An observable list the scheduler reads.
@MainActor @Observable final class FixtureEventsBox {
    var events: [EventSnapshot] = []
}
