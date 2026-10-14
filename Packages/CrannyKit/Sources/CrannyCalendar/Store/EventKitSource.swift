// CrannyCalendar/Store/EventKitSource.swift — the app's `EventSource`: one long-lived `EKEventStore`, confined to
// this actor so EventKit objects never cross threads, recreated after access is granted (ARCHITECTURE.md §7.4,
// R3 §4). It never asks for access: `PermissionsCenter` does that, and the store calls in only once granted.
// Each fetch converts every occurrence, so the per-calendar work (the colour in sRGB) is done once per calendar
// and fetch, not once per event.
import CoreGraphics
import CrannyCore
import EventKit
import Foundation

actor EventKitSource: EventSource {
    private var store: EKEventStore?

    func calendars() async throws -> [CalendarInfo] {
        let srgb = CGColorSpace(name: CGColorSpace.sRGB)
        return eventStore().calendars(for: .event).map { calendar in
            CalendarInfo(id: calendar.calendarIdentifier, title: calendar.title,
                         color: Self.rgb(calendar.cgColor, in: srgb), sourceTitle: calendar.source?.title ?? "",
                         isBirthdays: calendar.type == .birthday)
        }
    }

    func events(in interval: DateInterval) async throws -> [EventSnapshot] {
        let store = eventStore()
        let predicate = store.predicateForEvents(withStart: interval.start, end: interval.end, calendars: nil)
        var colors = CalendarColors()
        return store.events(matching: predicate).compactMap { Self.snapshot($0, colors: &colors) }
    }

    func reset() async { store = nil }

    // MARK: - Conversion (inside the actor: EKEvent never leaves it)

    private func eventStore() -> EKEventStore {
        if let store { return store }
        let created = EKEventStore()
        store = created
        return created
    }

    private static func snapshot(_ event: EKEvent, colors: inout CalendarColors) -> EventSnapshot? {
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
            color: colors.color(of: calendar),
            location: event.location,
            links: MeetingLinkDetector.links(url: event.url, location: event.location, notes: event.notes),
            isCancelled: event.status == .canceled,
            isDeclined: declined,
            isBirthday: calendar?.type == .birthday)
    }

    /// The calendar colour in sRGB (`space`; grey when EventKit has none).
    fileprivate static func rgb(_ color: CGColor?, in space: CGColorSpace?) -> RGB {
        let fallback = RGB(white: 0.6)
        guard let color, let space,
              let converted = color.converted(to: space, intent: .defaultIntent, options: nil),
              let c = converted.components else { return fallback }
        switch c.count {
        case 3...: return RGB(Double(c[0]), Double(c[1]), Double(c[2]))
        case 1...: return RGB(white: Double(c[0]))
        default: return fallback
        }
    }
}

/// The colours of the calendars seen during one fetch: each calendar's colour is converted to sRGB once, however many
/// of its events the fetch returns (a calendar's colour is not part of its events, so nothing outlives the fetch).
nonisolated private struct CalendarColors {
    private let srgb = CGColorSpace(name: CGColorSpace.sRGB)
    private var byCalendar: [String: RGB] = [:]

    mutating func color(of calendar: EKCalendar?) -> RGB {
        let id = calendar?.calendarIdentifier ?? ""
        if let known = byCalendar[id] { return known }
        let color = EventKitSource.rgb(calendar?.cgColor, in: srgb)
        byCalendar[id] = color
        return color
    }
}
