// CrannyCalendar/Store/Agenda.swift — what the Calendar widget lists for one day (DESIGN.md §7.2): all-day
// events first, then timed events; today's ended events dimmed (or hidden), the live or next event featured on
// two lines with Join — and, while another event is live, the meeting that "Meeting soon" announces as well, so
// clicking that activity lands on a row that can be joined. A pure function of the filtered events, the day and
// the time.
import Foundation

nonisolated struct Agenda: Equatable, Sendable {
    nonisolated enum Role: Equatable, Sendable {
        case allDay
        /// Ended (today: tertiary + strikethrough; earlier days: tertiary).
        case ended
        /// In progress now.
        case live
        /// The next event today: featured when nothing is live, or when it is the "Meeting soon" one.
        case next
        case upcoming
    }

    nonisolated struct Row: Identifiable, Equatable, Sendable {
        var event: EventSnapshot
        var role: Role
        var id: String { event.id }
    }

    var day: DateInterval
    var isToday: Bool
    var rows: [Row]
    /// The rows drawn on two lines with their relative time and Join, in list order: the live event that started
    /// last, else the next one; plus the "Meeting soon" event while another one is live. Only today has any.
    var featuredIDs: [String]

    /// Nothing left today: no all-day, live or upcoming event (ended ones do not count).
    var isEmptyToday: Bool { isToday && !rows.contains { $0.role != .ended } }
    var isEmpty: Bool { rows.isEmpty }
    var featured: [Row] { rows.filter { featuredIDs.contains($0.id) } }
    func isFeatured(_ row: Row) -> Bool { featuredIDs.contains(row.id) }

    /// - Parameters:
    ///   - events: filtered and sorted (`EventFilter.apply`).
    ///   - showsPastToday: `CalendarSettings.showsPastEventsToday`.
    ///   - soonID: the event "Meeting soon" shows (`MeetingTimeline.State.soon`), if any.
    static func make(events: [EventSnapshot], day: DateInterval, now: Date, isToday: Bool, showsPastToday: Bool,
                     soonID: String? = nil) -> Agenda {
        let onDay = events.filter { $0.overlaps(day) }
        let allDay = onDay.filter { !$0.isTimed }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        let timed = onDay.filter(\.isTimed).sorted(by: EventFilter.order)

        var rows = allDay.map { Row(event: $0, role: .allDay) }
        var featured: Set<String> = []
        if isToday {
            // Only meeting-like events are featured (a multi-day block stays an ordinary row).
            let live = timed.filter { $0.isMeetingLike && $0.isInProgress(at: now) }
            let liveFeature = live.max { ($0.start, $1.end) < ($1.start, $0.end) }   // latest start, then earliest end
            let upcoming = timed.filter { $0.isMeetingLike && $0.start > now }
            let nextID = liveFeature == nil ? upcoming.first?.id : upcoming.first { $0.id == soonID }?.id
            featured = Set([liveFeature?.id, nextID].compactMap(\.self))
            for event in timed {
                let role: Role
                if event.isInProgress(at: now) { role = .live }
                else if event.start > now || (event.start == now && event.end == now) { role = event.id == nextID ? .next : .upcoming }
                else { role = .ended }
                if role == .ended && !showsPastToday { continue }
                rows.append(Row(event: event, role: role))
            }
        } else {
            let isPast = day.end <= now
            rows += timed.map { Row(event: $0, role: isPast || $0.hasEnded(at: now) ? .ended : .upcoming) }
        }
        return Agenda(day: day, isToday: isToday, rows: rows, featuredIDs: rows.map(\.id).filter(featured.contains))
    }

    /// The first timed event that starts within `day` (for "No more events today" + tomorrow's first event).
    static func firstTimedEvent(in events: [EventSnapshot], day: DateInterval) -> EventSnapshot? {
        events.filter { $0.isTimed && day.contains($0.start) && $0.start < day.end }.min(by: EventFilter.order)
    }
}
