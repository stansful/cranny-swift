// CrannyCalendar/Store/EventKitSource.swift — the app's `EventSource`: one long-lived `EKEventStore`, confined to
// this actor so EventKit objects never cross threads, recreated after access is granted (ARCHITECTURE.md §7.4,
// R3 §4). It never asks for access: `PermissionsCenter` does that, and the store calls in only once granted.
import CoreGraphics
import CrannyCore
import EventKit
import Foundation

actor EventKitSource: EventSource {
    private var store: EKEventStore?

    func calendars() async throws -> [CalendarInfo] {
        eventStore().calendars(for: .event).map { calendar in
            CalendarInfo(id: calendar.calendarIdentifier, title: calendar.title,
                         color: Self.rgb(calendar.cgColor), sourceTitle: calendar.source?.title ?? "",
                         isBirthdays: calendar.type == .birthday)
        }
    }

    func events(in interval: DateInterval) async throws -> [EventSnapshot] {
        let store = eventStore()
        let predicate = store.predicateForEvents(withStart: interval.start, end: interval.end, calendars: nil)
        return store.events(matching: predicate).compactMap(Self.snapshot)
    }

    func reset() async { store = nil }

    // MARK: - Conversion (inside the actor: EKEvent never leaves it)

    private func eventStore() -> EKEventStore {
        if let store { return store }
        let created = EKEventStore()
        store = created
        return created
    }

    private static func snapshot(_ event: EKEvent) -> EventSnapshot? {
        guard let start = event.startDate, let end = event.endDate else { return nil }
        let calendar: EKCalendar? = event.calendar
        let base = event.eventIdentifier ?? event.calendarItemIdentifier
        let occurrence = event.occurrenceDate ?? start
        let declined = event.attendees?.first(where: \.isCurrentUser)?.participantStatus == .declined
        let title = (event.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return EventSnapshot(
            id: "\(base)@\(Int(occurrence.timeIntervalSinceReferenceDate))",
            eventIdentifier: event.eventIdentifier,
            title: title, start: start, end: end, isAllDay: event.isAllDay,
            calendarID: calendar?.calendarIdentifier ?? "",
            color: rgb(calendar?.cgColor),
            location: event.location,
            links: MeetingLinkDetector.links(url: event.url, location: event.location, notes: event.notes),
            isCancelled: event.status == .canceled,
            isDeclined: declined,
            isBirthday: calendar?.type == .birthday)
    }

    /// The calendar colour in sRGB (grey when EventKit has none).
    private static func rgb(_ color: CGColor?) -> RGB {
        let fallback = RGB(white: 0.6)
        guard let color, let space = CGColorSpace(name: CGColorSpace.sRGB),
              let converted = color.converted(to: space, intent: .defaultIntent, options: nil),
              let c = converted.components else { return fallback }
        switch c.count {
        case 3...: return RGB(Double(c[0]), Double(c[1]), Double(c[2]))
        case 1...: return RGB(white: Double(c[0]))
        default: return fallback
        }
    }
}
