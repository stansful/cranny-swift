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

    @Test func aMeetingSoonThatAppearsLateIsStillAnAlert() {
        // The Mac wakes 3 minutes before a meeting (lead 5): a new stage, a revision, and a wake when its minute
        // of P1 ends — not "already over" because the stage began on the clock two minutes earlier.
        let s = scheduler([T.event("standup", start: T.date(h: 10), link: "https://zoom.us/j/1")])
        time.now = T.date(h: 9, 57)
        s.replan()
        #expect(s.soonRevision == 1)
        #expect(s.state.soon?.alertUntil == T.date(h: 9, 58))
        #expect(s.nextWake == T.date(h: 9, 58))
        time.now = T.date(h: 9, 58)
        s.replan()
        #expect(s.soonRevision == 1)                                   // same stage
        #expect(s.state.soon?.alertUntil == T.date(h: 9, 58))           // shown at 09:57, not re-timed
        #expect(s.nextWake == T.date(h: 9, 59))
    }

    @Test func aClockChangeReArmsTheWakeForTheSameBoundary() async throws {
        // The wall clock jumps forward 10 minutes (`.NSSystemClockDidChange` reloads the store, which re-plans).
        // The boundary is the same instant, but the sleep must be re-armed with the shorter delay.
        let sleeps = SleepLog()
        let trigger = FixtureEventsBox()
        let event = T.event("call", start: T.date(h: 9, 30))
        let s = MeetingScheduler(events: { [event] }, leadMinutes: { 5 }, clock: time.clock,
                                 sleep: { duration in sleeps.append(duration); try await Task.sleep(for: .seconds(3600)) })
        s.start(trigger: { trigger.events.count })
        await settle()
        #expect(s.nextWake == T.date(h: 9, 25))
        #expect(sleeps.last == .milliseconds(25 * 60_000 + 50))

        time.now = T.date(h: 9, 10)
        trigger.events = [event]                                       // the reload after the clock change
        await settle()
        #expect(s.nextWake == T.date(h: 9, 25))
        #expect(sleeps.last == .milliseconds(15 * 60_000 + 50))
        #expect(sleeps.count == 2)
        s.stop()
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

/// The delays a scheduler asked to sleep for. `@unchecked Sendable`: guarded by a lock (the sleep runs in a task).
nonisolated final class SleepLog: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Duration] = []
    func append(_ duration: Duration) { lock.withLock { values.append(duration) } }
    var last: Duration? { lock.withLock { values.last } }
    var count: Int { lock.withLock { values.count } }
}
