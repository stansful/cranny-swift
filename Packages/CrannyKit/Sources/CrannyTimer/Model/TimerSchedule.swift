// CrannyTimer/Model/TimerSchedule.swift — the ONE wake-up a timer needs next (energy rule: no ticking timers,
// ARCHITECTURE.md §9.1–§9.2). The model sleeps to that date, handles the event and asks again.
import Foundation

/// Something that happens to a timer at a known date.
nonisolated enum TimerEvent: Equatable, Sendable {
    /// One minute left: the running activity's meaningful change (and the optional peek).
    case lastMinute
    /// The deadline: running → done.
    case finish
    /// "Timer done" has been shown for a minute: done → idle.
    case expire
}

nonisolated enum TimerSchedule {
    /// The next event and its date, or nil when nothing is pending (idle, paused).
    /// `lastMinuteSignalled` = the last-minute event already fired for this run (it fires once per run, and never
    /// for a run that starts inside its last minute).
    static func next(for state: TimerState, lastMinuteSignalled: Bool) -> (event: TimerEvent, date: Date)? {
        switch state.phase {
        case .idle, .paused:
            return nil
        case .running(let end):
            if !lastMinuteSignalled {
                return (.lastMinute, end.addingTimeInterval(-TimerLimits.lastMinute))
            }
            return (.finish, end)
        case .done(let at):
            return (.expire, at.addingTimeInterval(TimerLimits.doneLinger))
        }
    }

    /// Whether a run that has `remaining` seconds left right after a start / "+1 min" / adjustment still has its
    /// last-minute moment ahead of it.
    static func lastMinuteIsAhead(remaining: TimeInterval) -> Bool {
        remaining > TimerLimits.lastMinute
    }
}
