import Foundation
import Testing
@testable import CrannyCalendar

/// Scheduler boundaries (ARCHITECTURE.md §10.3), including DST and time-zone changes.
@Suite struct MeetingTimelineTests {
    private let meeting = T.event("standup", start: T.date(h: 10), minutes: 15, link: "https://zoom.us/j/1")

    @Test func nothingBeforeTheLeadTime() {
        let state = MeetingTimeline.state(events: [meeting], now: T.date(h: 9, 54), leadMinutes: 5)
        #expect(state == .none)
    }

    @Test func leadStageThenLastMinuteThenInProgress() throws {
        let lead = try #require(MeetingTimeline.state(events: [meeting], now: T.date(h: 9, 55), leadMinutes: 5).soon)
        #expect(lead.stage == .lead)
        #expect(lead.stageStart == T.date(h: 9, 55))
        #expect(lead.alertUntil == T.date(h: 9, 56))

        let last = try #require(MeetingTimeline.state(events: [meeting], now: T.date(h: 9, 59), leadMinutes: 5).soon)
        #expect(last.stage == .lastMinute)
        #expect(last.key != lead.key)                                      // a second meaningful change

        let running = MeetingTimeline.state(events: [meeting], now: T.date(h: 10, 3), leadMinutes: 5)
        #expect(running.soon == nil)
        #expect(running.current?.id == "standup")
        #expect(MeetingTimeline.state(events: [meeting], now: T.date(h: 10, 15), leadMinutes: 5) == .none)
    }

    @Test func aStageThatAppearsLateAlertsFromWhenItIsShown() throws {
        // Woken, launched or the meeting created 3 minutes before the start, with a 5-minute lead: the stage began
        // two minutes ago on the clock, but it is shown now, so the P1 alert lasts a minute from now.
        let now = T.date(h: 9, 57)
        let late = try #require(MeetingTimeline.state(events: [meeting], now: now, leadMinutes: 5).soon)
        #expect(late.stage == .lead)
        #expect(late.stageStart == T.date(h: 9, 55))
        #expect(late.shownAt == now)
        #expect(late.alertUntil == T.date(h: 9, 58))
        #expect(MeetingTimeline.nextBoundary(events: [meeting], now: now, leadMinutes: 5, state: .init(soon: late)) == T.date(h: 9, 58))

        // The next plan of the same stage keeps when it was shown: the alert settles to P2.
        let later = try #require(MeetingTimeline.state(events: [meeting], now: T.date(h: 9, 58), leadMinutes: 5,
                                                       previous: .init(soon: late)).soon)
        #expect(later.shownAt == now)
        #expect(later.alertUntil == T.date(h: 9, 58))
        // The last minute is a new stage: shown on time, alerting again.
        let last = try #require(MeetingTimeline.state(events: [meeting], now: T.date(h: 9, 59), leadMinutes: 5,
                                                      previous: .init(soon: later)).soon)
        #expect(last.stage == .lastMinute)
        #expect(last.shownAt == T.date(h: 9, 59))
        #expect(last.alertUntil == T.date(h: 10))
    }

    @Test func raisingTheLeadTimeNearAMeetingShowsANewStage() throws {
        // Lead 1 at 09:57: nothing yet. Raised to 10 at 09:57: the lead stage appears now and alerts from now.
        #expect(MeetingTimeline.state(events: [meeting], now: T.date(h: 9, 57), leadMinutes: 1).soon == nil)
        let raised = try #require(MeetingTimeline.state(events: [meeting], now: T.date(h: 9, 57), leadMinutes: 10).soon)
        #expect(raised.stageStart == T.date(h: 9, 50))
        #expect(raised.alertUntil == T.date(h: 9, 58))
    }

    @Test func oneMinuteLeadHasOnlyTheLastMinuteStage() {
        #expect(MeetingTimeline.state(events: [meeting], now: T.date(h: 9, 58), leadMinutes: 1).soon == nil)
        #expect(MeetingTimeline.state(events: [meeting], now: T.date(h: 9, 59, s: 30), leadMinutes: 1).soon?.stage == .lastMinute)
    }

    @Test func leadMinutesAreClamped() {
        #expect(MeetingTimeline.leadInterval(0) == 60)
        #expect(MeetingTimeline.leadInterval(90) == 30 * 60)
    }

    @Test func allDayEventsNeverBecomeMeetings() {
        let holiday = T.event("holiday", start: T.date(h: 0), minutes: 1440, allDay: true)
        #expect(MeetingTimeline.state(events: [holiday], now: T.date(h: 12), leadMinutes: 5) == .none)
        #expect(MeetingTimeline.nextBoundary(events: [holiday], now: T.date(h: 12), leadMinutes: 5) == nil)
    }

    @Test func longBlocksAreNotMeetings() {
        let conference = T.event("conference", start: T.date(2026, 10, 13, h: 9), minutes: 3 * 24 * 60)
        let state = MeetingTimeline.state(events: [conference], now: T.date(), leadMinutes: 5)
        #expect(state == .none)
        let workday = T.event("workday", start: T.date(h: 9), minutes: 11 * 60)        // under 12 h still counts
        #expect(MeetingTimeline.state(events: [workday], now: T.date(), leadMinutes: 5).current?.id == "workday")
    }

    @Test func overlappingMeetingsPickTheLatestStart() {
        let long = T.event("all-hands", start: T.date(h: 9), minutes: 120)
        let state = MeetingTimeline.state(events: [long, T.event("review", start: T.date(h: 9, 30), minutes: 30), meeting],
                                          now: T.date(h: 9, 56), leadMinutes: 5)
        #expect(state.current?.id == "review")
        #expect(state.soon?.event.id == "standup")
    }

    @Test func boundariesWalkThroughTheMeeting() {
        // As the scheduler does: each plan carries the previous state, so a stage keeps when it was shown.
        var now = T.date(h: 8)
        var state = MeetingTimeline.state(events: [meeting], now: now, leadMinutes: 5)
        var visited: [Date] = []
        while let next = MeetingTimeline.nextBoundary(events: [meeting], now: now, leadMinutes: 5, state: state) {
            visited.append(next)
            now = next
            state = MeetingTimeline.state(events: [meeting], now: now, leadMinutes: 5, previous: state)
        }
        #expect(visited == [T.date(h: 9, 55), T.date(h: 9, 56), T.date(h: 9, 59), T.date(h: 10), T.date(h: 10, 15)])
    }

    @Test func noBoundaryWhenNothingIsUpcoming() {
        #expect(MeetingTimeline.nextBoundary(events: [], now: T.date(), leadMinutes: 5) == nil)
        #expect(MeetingTimeline.nextBoundary(events: [meeting], now: T.date(h: 11), leadMinutes: 5) == nil)
    }

    @Test func daylightSavingDoesNotMoveBoundaries() {
        // Berlin, 2026-03-29: 02:00 CET jumps to 03:00 CEST. A 03:15 meeting with a 30-minute lead is "soon" 30 real
        // minutes earlier: 01:45 wall time. Wall-clock arithmetic would say 02:45, an hour that does not exist.
        let start = T.date(2026, 3, 29, h: 3, 15)
        let event = T.event("dst", start: start, minutes: 30)
        let boundary = MeetingTimeline.nextBoundary(events: [event], now: T.date(2026, 3, 29, h: 1), leadMinutes: 30)
        #expect(boundary == start.addingTimeInterval(-30 * 60))
        let wall = T.calendar().dateComponents([.hour, .minute], from: boundary ?? .distantPast)
        #expect(wall.hour == 1 && wall.minute == 45)
        #expect(MeetingTimeline.state(events: [event], now: start.addingTimeInterval(-29 * 60), leadMinutes: 30).soon?.event.id == "dst")
        // Falling back (2026-10-25, 03:00 CEST → 02:00 CET): a 02:30 CET meeting's lead starts 30 real minutes before.
        let fallStart = T.date(2026, 10, 25, h: 2, 30).addingTimeInterval(3600)      // the second 02:30 (CET)
        let fall = T.event("fall", start: fallStart, minutes: 30)
        #expect(MeetingTimeline.nextBoundary(events: [fall], now: fallStart.addingTimeInterval(-2 * 3600), leadMinutes: 30)
                == fallStart.addingTimeInterval(-30 * 60))
    }

    @Test func timeZoneChangeKeepsAbsoluteInstants() {
        // The same instants seen from another zone produce the same state and boundaries.
        let event = T.event("call", start: T.date(h: 15, zone: "Asia/Tokyo"), minutes: 30)
        let now = T.date(h: 14, 58, zone: "Asia/Tokyo")
        let state = MeetingTimeline.state(events: [event], now: now, leadMinutes: 5)
        #expect(state.soon?.stage == .lead)
        #expect(MeetingTimeline.nextBoundary(events: [event], now: now, leadMinutes: 5) == T.date(h: 14, 59, zone: "Asia/Tokyo"))
    }
}
