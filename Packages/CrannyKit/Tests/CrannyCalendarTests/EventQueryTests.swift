import CrannyCore
import Foundation
import Testing
@testable import CrannyCalendar

/// Windowing and filtering against plain values (no EventKit), ARCHITECTURE.md §10.3.
@Suite struct EventQueryTests {
    @Test func defaultWindowIsTodayAndTomorrow() {
        let cal = T.calendar()
        let window = EventWindow.interval(containing: T.date(h: 15, 30), daysBehind: 0, daysAhead: 1, calendar: cal)
        #expect(window.start == T.date(h: 0))
        #expect(window.end == T.date(2026, 10, 16, h: 0))
    }

    @Test func windowReachesBackAndClampsToSevenDays() {
        let cal = T.calendar()
        let window = EventWindow.interval(containing: T.date(), daysBehind: 2, daysAhead: 30, calendar: cal)
        #expect(window.start == T.date(2026, 10, 12, h: 0))
        #expect(window.end == T.date(2026, 10, 22, h: 0))                   // 7 days ahead + today
        let negative = EventWindow.interval(containing: T.date(), daysBehind: -4, daysAhead: -1, calendar: cal)
        #expect(negative.start == T.date(h: 0) && negative.end == T.date(2026, 10, 15, h: 0))
    }

    @Test func daylightSavingDaysAreCalendarDays() {
        let cal = T.calendar()
        // Berlin springs forward on 2026-03-29 (23 h) and falls back on 2026-10-25 (25 h).
        let spring = EventWindow.day(offset: 0, from: T.date(2026, 3, 29, h: 12), calendar: cal)
        #expect(spring.duration == 23 * 3600)
        let fall = EventWindow.day(offset: 0, from: T.date(2026, 10, 25, h: 12), calendar: cal)
        #expect(fall.duration == 25 * 3600)
        // A window that spans the change still ends at local midnight.
        let window = EventWindow.interval(containing: T.date(2026, 10, 24, h: 22), daysBehind: 0, daysAhead: 1, calendar: cal)
        #expect(window.end == T.date(2026, 10, 26, h: 0))
        #expect(window.duration == 49 * 3600)
    }

    @Test func timeZoneDecidesWhereTodayStarts() {
        let instant = T.date(h: 23, zone: "America/New_York")                  // already tomorrow in Tokyo
        let ny = EventWindow.interval(containing: instant, daysBehind: 0, daysAhead: 0, calendar: T.calendar("America/New_York"))
        let tokyo = EventWindow.interval(containing: instant, daysBehind: 0, daysAhead: 0, calendar: T.calendar("Asia/Tokyo"))
        #expect(ny.start == T.date(h: 0, zone: "America/New_York"))
        #expect(tokyo.start == T.date(2026, 10, 15, h: 0, zone: "Asia/Tokyo"))
        #expect(ny != tokyo)
    }

    @Test func filterHidesCancelledDeclinedAndHiddenCalendars() {
        let start = T.date()
        let events = [
            T.event("ok", start: start),
            T.event("cancelled", start: start, cancelled: true),
            T.event("declined", start: start, declined: true),
            T.event("hidden", start: start, calendarID: "private"),
        ]
        let filter = EventFilter(hiddenCalendarIDs: ["private"])
        #expect(filter.apply(events).map(\.id) == ["ok"])
    }

    @Test func allDayAndBirthdayOptions() {
        let day = T.date(h: 0)
        let events = [T.event("allday", start: day, minutes: 1440, allDay: true),
                      T.event("birthday", start: day, minutes: 1440, allDay: true, birthday: true),
                      T.event("timed", start: T.date(h: 9))]
        #expect(EventFilter().apply(events).map(\.id) == ["allday", "timed"])                        // defaults
        #expect(EventFilter(includesAllDay: false).apply(events).map(\.id) == ["timed"])
        #expect(EventFilter(includesAllDay: false, includesBirthdays: true).apply(events).map(\.id) == ["birthday", "timed"])
    }

    @Test func sortedByStartWithAllDayFirst() {
        let events = [T.event("b", start: T.date(h: 11)), T.event("a", start: T.date(h: 9)),
                      T.event("all", start: T.date(h: 0), minutes: 1440, allDay: true), T.event("c", start: T.date(h: 0), minutes: 15)]
        #expect(EventFilter().apply(events).map(\.id) == ["all", "c", "a", "b"])
    }

    @Test @MainActor func filterFollowsSettings() {
        let settings = CrannyServices.preview().settings
        settings[CalendarSettings.hiddenCalendarIDs] = ["x"]
        settings[CalendarSettings.includesAllDay] = false
        let filter = EventFilter(settings: settings)
        #expect(filter == EventFilter(hiddenCalendarIDs: ["x"], includesAllDay: false, includesBirthdays: false))
    }

    @Test func overlapIncludesMultiDayAndZeroLengthEvents() {
        let today = EventWindow.day(offset: 0, from: T.date(), calendar: T.calendar())
        #expect(T.event("trip", start: T.date(2026, 10, 13, h: 18), minutes: 24 * 60).overlaps(today))
        #expect(T.event("reminder", start: T.date(h: 0), minutes: 0).overlaps(today))
        #expect(!T.event("yesterday", start: T.date(2026, 10, 13, h: 9)).overlaps(today))
        #expect(!T.event("ends at midnight", start: T.date(2026, 10, 13, h: 23), minutes: 60).overlaps(today))
    }
}
