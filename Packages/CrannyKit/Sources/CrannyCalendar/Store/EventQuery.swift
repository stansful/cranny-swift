// CrannyCalendar/Store/EventQuery.swift — which events Cranny fetches and which it shows (ARCHITECTURE.md §7.4).
// Pure functions of their inputs (dates, a `Calendar`, settings values): windowing is DST-safe because it
// works in calendar days, never in multiples of 86 400 s.
import CrannyCore
import Foundation

nonisolated enum EventWindow {
    /// The fetch window: start of today − `daysBehind` days … start of today + `daysAhead` + 1 days.
    static func interval(containing now: Date, daysBehind: Int, daysAhead: Int, calendar: Calendar) -> DateInterval {
        let behind = clampDays(daysBehind), ahead = clampDays(daysAhead)
        let today = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: -behind, to: today) ?? today
        let end = calendar.date(byAdding: .day, value: ahead + 1, to: today) ?? today.addingTimeInterval(86_400)
        return DateInterval(start: start, end: max(end, start))
    }

    /// One calendar day, `offset` days from the day containing `now` (0 = today). 23 or 25 hours long on
    /// daylight-saving changes.
    static func day(offset: Int, from now: Date, calendar: Calendar) -> DateInterval {
        let today = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: offset, to: today) ?? today
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        return DateInterval(start: start, end: max(end, start))
    }

    static func clampDays(_ days: Int) -> Int { min(max(days, CalendarSettings.dayRange.lowerBound), CalendarSettings.dayRange.upperBound) }
}

/// The user's filters (Settings ▸ Calendar). Cancelled and declined events are always hidden.
nonisolated struct EventFilter: Equatable, Sendable {
    var hiddenCalendarIDs: Set<String> = []
    var includesAllDay = true
    var includesBirthdays = false

    func includes(_ event: EventSnapshot) -> Bool {
        guard !event.isCancelled, !event.isDeclined, !hiddenCalendarIDs.contains(event.calendarID) else { return false }
        if event.isBirthday { return includesBirthdays }
        return includesAllDay || !event.isAllDay
    }

    /// Filtered and sorted: start, then all-day before timed, then end, then title (stable for equal events).
    func apply(_ events: [EventSnapshot]) -> [EventSnapshot] {
        events.filter(includes).sorted(by: Self.order)
    }

    static func order(_ a: EventSnapshot, _ b: EventSnapshot) -> Bool {
        if a.start != b.start { return a.start < b.start }
        if a.isAllDay != b.isAllDay { return a.isAllDay }
        if a.end != b.end { return a.end < b.end }
        if a.title != b.title { return a.title.localizedStandardCompare(b.title) == .orderedAscending }
        return a.id < b.id
    }
}

extension EventFilter {
    /// The filter the settings describe.
    @MainActor init(settings: SettingsStore) {
        self.init(hiddenCalendarIDs: Set(settings[CalendarSettings.hiddenCalendarIDs]),
                  includesAllDay: settings[CalendarSettings.includesAllDay],
                  includesBirthdays: settings[CalendarSettings.includesBirthdays])
    }
}
