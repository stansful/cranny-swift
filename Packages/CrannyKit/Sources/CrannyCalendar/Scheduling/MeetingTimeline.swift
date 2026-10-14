// CrannyCalendar/Scheduling/MeetingTimeline.swift — the pure core of the meeting activities (ARCHITECTURE.md
// §7.4, DESIGN.md §9.2): which event is "soon" or "in progress" at an instant, and the next instant at which
// that answer (or anything the widget shows) can change. Everything is absolute `Date`s, so daylight-saving
// and time-zone changes cannot shift a boundary; only the fetch window depends on the calendar.
import Foundation

nonisolated enum MeetingTimeline {
    /// How long a "Meeting soon" stage stays a P1 alert after it is first shown, before it settles to P2
    /// (DESIGN.md §9.2: "P1 when it appears, then P2"). Long enough for the auto-peek and a glance.
    static let alertHold: TimeInterval = 60
    /// The second alert: one minute before the start.
    static let lastMinute: TimeInterval = 60

    nonisolated enum Stage: String, Equatable, Sendable {
        /// From `leadMinutes` before the start.
        case lead
        /// The last minute before the start (a second meaningful change).
        case lastMinute
    }

    nonisolated struct Soon: Equatable, Sendable {
        var event: EventSnapshot
        var stage: Stage
        /// When the current stage begins on the clock: the lead time, or one minute before the start.
        var stageStart: Date
        /// When this stage was first shown. `stageStart` when Cranny was running on time; later when the stage
        /// appears late — after a wake or a launch, for a meeting created or accepted within the lead time, or
        /// when the lead time grows. The P1 alert is measured from here, so a late stage still alerts.
        var shownAt: Date
        /// The end of the P1 alert (auto-peek, VoiceOver announcement); P2 afterwards.
        var alertUntil: Date { shownAt.addingTimeInterval(MeetingTimeline.alertHold) }
        /// Identity of a "meaningful change": a new event, or the same event entering its last minute.
        var key: String { event.id + "|" + stage.rawValue }
    }

    nonisolated struct State: Equatable, Sendable {
        var soon: Soon?
        /// The event in progress (the one that started last when several overlap).
        var current: EventSnapshot?
        static let none = State()
    }

    /// The meeting state at `now`. `events` must already be filtered; only meeting-like events count (timed,
    /// under 12 hours: no all-day events, birthdays or multi-day blocks).
    /// - Parameter previous: the state of the last plan. A stage that was already showing keeps its `shownAt`;
    ///   a new one is shown now.
    static func state(events: [EventSnapshot], now: Date, leadMinutes: Int, previous: State = .none) -> State {
        let lead = leadInterval(leadMinutes)
        let timed = events.filter(\.isMeetingLike)
        let current = timed.filter { $0.isInProgress(at: now) }
            .max { ($0.start, $1.end) < ($1.start, $0.end) }
        let soon = timed.filter { $0.start > now && $0.start.timeIntervalSince(now) <= lead }
            .min(by: EventFilter.order)
            .map { event -> Soon in
                let untilStart = event.start.timeIntervalSince(now)
                let stage: Stage = untilStart <= lastMinute ? .lastMinute : .lead
                let stageStart = event.start.addingTimeInterval(-(stage == .lastMinute ? lastMinute : lead))
                var soon = Soon(event: event, stage: stage, stageStart: stageStart, shownAt: max(stageStart, now))
                if let shown = previous.soon, shown.key == soon.key { soon.shownAt = shown.shownAt }
                return soon
            }
        return State(soon: soon, current: current)
    }

    /// The next instant after `now` at which `state(…)`, an alert's priority, or a widget row's role changes:
    /// each timed event's lead start, last minute, start and end, plus the end of the current alert.
    /// nil = nothing ahead in `events` (no timer at all: ARCHITECTURE.md §9.2).
    /// - Parameter state: the state at `now` (the scheduler's plan); computed afresh when nil.
    static func nextBoundary(events: [EventSnapshot], now: Date, leadMinutes: Int, state: State? = nil) -> Date? {
        let lead = leadInterval(leadMinutes)
        var next: Date?
        func consider(_ date: Date) { if date > now, next.map({ date < $0 }) ?? true { next = date } }
        for event in events where event.isTimed {             // all timed events: the widget's rows change too
            consider(event.start.addingTimeInterval(-lead))
            consider(event.start.addingTimeInterval(-lastMinute))
            consider(event.start)
            consider(event.end)
        }
        if let soon = (state ?? self.state(events: events, now: now, leadMinutes: leadMinutes)).soon { consider(soon.alertUntil) }
        return next
    }

    static func leadInterval(_ minutes: Int) -> TimeInterval {
        TimeInterval(min(max(minutes, CalendarSettings.leadRange.lowerBound), CalendarSettings.leadRange.upperBound) * 60)
    }
}
