// CrannyTimer/Model/TimerFormat.swift — numbers and durations through FormatStyle only (ARCHITECTURE.md §8.7 rule 5):
// digits "4:59" / "1:30:00", spoken "4 minutes, 59 seconds", short "25 min", end time "14:35" / "2:35 PM".
import Foundation

nonisolated enum TimerFormat {
    /// What a preset chip shows: a number and its unit ("25" + min).
    enum PresetUnit: Equatable, Sendable { case hours, minutes, seconds, clock }

    /// The digits of a countdown: "m:ss" below an hour, "h:mm:ss" from an hour on.
    static func clock(_ seconds: Int, locale: Locale = .autoupdatingCurrent) -> String {
        let s = max(seconds, 0)
        let pattern: Duration.TimeFormatStyle.Pattern = s >= 3600 ? .hourMinuteSecond : .minuteSecond
        return Duration.seconds(s).formatted(.time(pattern: pattern).locale(locale))
    }

    /// VoiceOver: "4 minutes, 59 seconds" / "4 минуты 59 секунд".
    static func spoken(_ seconds: Int, locale: Locale = .autoupdatingCurrent) -> String {
        Duration.seconds(max(seconds, 0))
            .formatted(.units(allowed: [.hours, .minutes, .seconds], width: .wide).locale(locale))
    }

    /// Chips, ⌘K and subtitles: "25 min", "1h 30m" (narrow once there are two units, so chips stay short).
    static func short(_ seconds: Int, locale: Locale = .autoupdatingCurrent) -> String {
        let s = max(seconds, 0)
        let units = (s >= 3600 ? 1 : 0) + (s % 3600 >= 60 ? 1 : 0) + (s % 60 > 0 ? 1 : 0)
        return Duration.seconds(s).formatted(.units(allowed: [.hours, .minutes, .seconds],
                                                    width: units > 1 ? .narrow : .abbreviated).locale(locale))
    }

    /// The end time, 12/24-hour from the locale ("14:35", "2:35 PM").
    static func time(_ date: Date, locale: Locale = .autoupdatingCurrent) -> String {
        date.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(locale))
    }

    /// A preset's number and unit for the 2 × 2 tiles: whole hours, whole minutes, seconds below a minute, else the
    /// clock form ("1:30") without a unit.
    static func presetFace(_ seconds: Int, locale: Locale = .autoupdatingCurrent) -> (value: String, unit: PresetUnit) {
        let s = max(seconds, 1)
        if s >= 3600, s % 3600 == 0 { return ((s / 3600).formatted(.number.locale(locale)), .hours) }
        if s % 60 == 0 { return ((s / 60).formatted(.number.locale(locale)), .minutes) }
        if s < 60 { return (s.formatted(.number.locale(locale)), .seconds) }
        return (clock(s, locale: locale), .clock)
    }
}
