// CrannyCalendar/Store/EventSnapshot.swift — immutable, thread-safe copies of EventKit objects.
// EventKit objects never leave `EventKitSource`; everything above it works on these values, so the
// windowing, filtering and scheduling logic is tested without EventKit (ARCHITECTURE.md §10.3).
import CrannyCore
import Foundation

/// One occurrence of an event. Recurring events produce one snapshot per occurrence.
nonisolated struct EventSnapshot: Identifiable, Hashable, Sendable {
    /// Stable per occurrence: the event identifier plus the occurrence's start.
    var id: String
    /// `EKEvent.eventIdentifier`, used to open the event in Calendar. nil for fixtures.
    var eventIdentifier: String?
    var title: String
    var start: Date
    var end: Date
    var isAllDay: Bool
    var calendarID: String
    /// The calendar's colour as stored (not yet contrast-guarded; see `EventColor`).
    var color: RGB
    var location: String?
    /// Meeting links found in the URL, location and notes, in search order, without duplicates.
    var links: [MeetingLink]
    var isCancelled: Bool
    /// The current user declined the invitation.
    var isDeclined: Bool
    var isBirthday: Bool

    init(id: String, eventIdentifier: String? = nil, title: String, start: Date, end: Date, isAllDay: Bool = false,
         calendarID: String, color: RGB, location: String? = nil, links: [MeetingLink] = [],
         isCancelled: Bool = false, isDeclined: Bool = false, isBirthday: Bool = false) {
        self.id = id; self.eventIdentifier = eventIdentifier; self.title = title
        self.start = start; self.end = max(end, start); self.isAllDay = isAllDay
        self.calendarID = calendarID; self.color = color; self.location = location; self.links = links
        self.isCancelled = isCancelled; self.isDeclined = isDeclined; self.isBirthday = isBirthday
    }

    /// Not an all-day event or a birthday.
    var isTimed: Bool { !isAllDay && !isBirthday }

    /// Timed and shorter than 12 hours: can be featured as "Now"/"Next" and become a meeting activity. A
    /// three-day conference entered with times must not sit in the notch for three days.
    var isMeetingLike: Bool { isTimed && end.timeIntervalSince(start) < Self.longestMeeting }
    static let longestMeeting: TimeInterval = 12 * 3600

    func isInProgress(at now: Date) -> Bool { start <= now && now < end }
    func hasEnded(at now: Date) -> Bool { end <= now && !(start == end && start == now) }

    /// The first link whose service the user allows (Settings ▸ Calendar ▸ Meeting links).
    func link(allowing services: Set<MeetingService>) -> MeetingLink? {
        links.first { services.contains($0.service) }
    }

    /// `location` without any URLs in it ("Room 4; https://zoom.us/j/1" → "Room 4"); nil when nothing readable is
    /// left (a meeting link pasted as the location says nothing to read).
    var readableLocation: String? {
        guard let location else { return nil }
        let text = URLScanner.removingURLs(from: location)
        return text.isEmpty ? nil : text
    }

    /// Whether the event overlaps `interval` (zero-length events count when they start inside it).
    func overlaps(_ interval: DateInterval) -> Bool {
        if start == end { return interval.start <= start && start < interval.end }
        return start < interval.end && end > interval.start
    }
}

/// A calendar the user can show or hide (Settings ▸ Calendar ▸ Calendars).
nonisolated struct CalendarInfo: Identifiable, Hashable, Sendable {
    var id: String
    var title: String
    var color: RGB
    /// The account it belongs to ("iCloud", "Google", "On My Mac").
    var sourceTitle: String
    var isBirthdays: Bool

    init(id: String, title: String, color: RGB, sourceTitle: String, isBirthdays: Bool = false) {
        self.id = id; self.title = title; self.color = color; self.sourceTitle = sourceTitle; self.isBirthdays = isBirthdays
    }
}
