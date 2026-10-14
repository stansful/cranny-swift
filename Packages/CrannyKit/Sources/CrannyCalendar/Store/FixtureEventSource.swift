// CrannyCalendar/Store/FixtureEventSource.swift — an in-memory `EventSource` and the module's sample day:
// tests, `#Preview`s, the Settings "Simulate" chips and the onboarding stage (never EventKit, never a prompt).
import CrannyCore
import Foundation

actor FixtureEventSource: EventSource {
    private(set) var storedEvents: [EventSnapshot]
    private(set) var storedCalendars: [CalendarInfo]
    /// Tests: make the next fetches fail.
    private(set) var failure: CalendarError?
    /// Tests: how often each call happened, and the last window asked for.
    private(set) var eventFetches = 0
    private(set) var resets = 0
    private(set) var lastInterval: DateInterval?

    init(events: [EventSnapshot] = [], calendars: [CalendarInfo] = [], failure: CalendarError? = nil) {
        storedEvents = events
        storedCalendars = calendars
        self.failure = failure
    }

    func calendars() async throws -> [CalendarInfo] {
        if let failure { throw failure }
        return storedCalendars
    }

    func events(in interval: DateInterval) async throws -> [EventSnapshot] {
        eventFetches += 1
        lastInterval = interval
        if let failure { throw failure }
        return storedEvents.filter { $0.overlaps(interval) }
    }

    func reset() async { resets += 1 }

    func set(events: [EventSnapshot]) { storedEvents = events }
    func set(calendars: [CalendarInfo]) { storedCalendars = calendars }
    func set(failure: CalendarError?) { self.failure = failure }
}

/// A plausible day around `now`, in the user's language: an event in progress, a meeting in four minutes with a
/// Zoom link, an ended event and later ones, tomorrow's first meeting and an all-day event.
enum CalendarSamples {
    static let work = CalendarInfo(id: "sample.work", title: String(localized: "Work", bundle: .module, comment: "Calendar sample data: calendar name"),
                                   color: RGB(hex: 0x1BADF8), sourceTitle: "iCloud")
    static let home = CalendarInfo(id: "sample.home", title: String(localized: "Personal", bundle: .module, comment: "Calendar sample data: calendar name"),
                                   color: RGB(hex: 0x63DA38), sourceTitle: "iCloud")
    static let team = CalendarInfo(id: "sample.team", title: String(localized: "Team", bundle: .module, comment: "Calendar sample data: calendar name"),
                                   color: RGB(hex: 0xCC73E1), sourceTitle: "Google")
    static var calendars: [CalendarInfo] { [work, team, home] }

    /// Times sit on quarter hours (as real calendars do), except the meeting that starts in exactly `soonIn` minutes
    /// (4 by default; pass the lead time when it is shorter, so "Meeting soon" is active in the sample).
    static func events(around now: Date, soonIn: Int = 4, calendar: Calendar = .autoupdatingCurrent) -> [EventSnapshot] {
        let minute = calendar.component(.minute, from: now)
        let wholeMinute = calendar.date(bySetting: .second, value: 0, of: now).map { $0 > now ? $0.addingTimeInterval(-60) : $0 } ?? now
        let quarter = wholeMinute.addingTimeInterval(TimeInterval(-(minute % 15) * 60))
        let today = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today.addingTimeInterval(86_400)
        let zoom = URL(string: "https://zoom.us/j/5551234567?pwd=sample")
        func event(_ id: String, _ title: String, _ start: Date, minutes: Int, _ cal: CalendarInfo,
                   location: String? = nil, link: URL? = nil, allDay: Bool = false) -> EventSnapshot {
            EventSnapshot(id: "sample.\(id)", title: title, start: start,
                          end: allDay ? tomorrow : start.addingTimeInterval(TimeInterval(minutes * 60)), isAllDay: allDay,
                          calendarID: cal.id, color: cal.color, location: location,
                          links: link.map { [MeetingLink(service: .zoom, url: $0)] } ?? [])
        }
        func q(_ minutes: Int) -> Date { quarter.addingTimeInterval(TimeInterval(minutes * 60)) }
        return [
            event("focus", String(localized: "Focus time", bundle: .module, comment: "Calendar sample data: event title"),
                  q(-105), minutes: 60, home),
            event("review", String(localized: "Design review", bundle: .module, comment: "Calendar sample data: event title"),
                  q(-15), minutes: 45, team, location: String(localized: "Room 4", bundle: .module, comment: "Calendar sample data: event location")),
            event("standup", String(localized: "Team standup", bundle: .module, comment: "Calendar sample data: event title"),
                  wholeMinute.addingTimeInterval(TimeInterval(max(soonIn, 1) * 60)), minutes: 15, work, location: zoom?.absoluteString, link: zoom),
            event("lunch", String(localized: "Lunch with Ana", bundle: .module, comment: "Calendar sample data: event title"),
                  q(90), minutes: 60, home),
            event("sync", String(localized: "Roadmap sync", bundle: .module, comment: "Calendar sample data: event title"),
                  q(180), minutes: 30, work, link: zoom),
            event("tomorrow", String(localized: "Planning", bundle: .module, comment: "Calendar sample data: event title"),
                  tomorrow.addingTimeInterval(10 * 3600), minutes: 60, work),
            event("release", String(localized: "Release day", bundle: .module, comment: "Calendar sample data: all-day event title"),
                  today, minutes: 0, team, allDay: true),
        ]
    }
}
