// CrannyCalendar/UI/CalendarFormat.swift — every date, time and duration the module shows, through `FormatStyle`
// (12/24-hour clock and word order from the locale, DESIGN.md §17), and the localized phrases around them.
// Durations are whole minutes chosen by `MinuteMath`; the formatter only spells them ("4m" / "4 мин"). The band's
// abbreviations take a `CalendarLanguage`, so tests check them in English and Russian (DESIGN.md §9.1).
import Foundation

/// Where the module's words and formats come from: the app's language (default), or one fixed localization of
/// the catalog with its locale (tests of the band's abbreviations, which must fit their slot in both languages).
struct CalendarLanguage {
    let bundle: Bundle
    let locale: Locale

    static var app: CalendarLanguage { CalendarLanguage(bundle: .module, locale: .autoupdatingCurrent) }

    /// The catalog's `code` localization ("en", "ru"), or nil when the module bundle has none.
    static func named(_ code: String) -> CalendarLanguage? {
        guard let path = Bundle.module.path(forResource: code, ofType: "lproj"), let bundle = Bundle(path: path) else { return nil }
        return CalendarLanguage(bundle: bundle, locale: Locale(identifier: code))
    }
}

enum CalendarFormat {
    // MARK: Dates and times

    /// "10:30" / "10:30 AM".
    static func time(_ date: Date) -> String { date.formatted(.dateTime.hour().minute()) }
    /// "10:30" without AM/PM (the band has no room; context makes it unambiguous).
    static func bandTime(_ date: Date, language: CalendarLanguage = .app) -> String {
        date.formatted(.dateTime.hour(.defaultDigits(amPM: .omitted)).minute().locale(language.locale))
    }
    /// "10:30–11:00".
    static func timeRange(_ start: Date, _ end: Date) -> String {
        (start..<max(end, start)).formatted(.interval.hour().minute())
    }
    /// "Tue" (drawn uppercase by the `micro` style).
    static func weekday(_ date: Date) -> String { date.formatted(.dateTime.weekday(.abbreviated)) }
    /// "14 October" / "October 14" / "14 октября".
    static func dayMonth(_ date: Date) -> String { date.formatted(.dateTime.day().month(.wide)) }
    /// "14 Oct" / "Oct 14" / "14 окт." (narrow headers).
    static func dayMonthShort(_ date: Date) -> String { date.formatted(.dateTime.day().month(.abbreviated)) }
    /// "14" (the day strip and the 2-cell date).
    static func dayNumber(_ date: Date) -> String { date.formatted(.dateTime.day()) }
    /// "Wednesday, 15 October" (VoiceOver, tooltips).
    static func fullDate(_ date: Date) -> String { date.formatted(.dateTime.weekday(.wide).day().month(.wide)) }

    // MARK: Durations

    /// "4m", "1h 5m" / "4 мин", "1 ч 5 мин".
    static func duration(minutes: Int, language: CalendarLanguage = .app) -> String {
        Duration.seconds(max(minutes, 0) * 60).formatted(.units(allowed: [.hours, .minutes], width: .narrow).locale(language.locale))
    }
    /// "4 minutes", "1 hour, 5 minutes" (VoiceOver).
    static func spokenDuration(minutes: Int) -> String {
        Duration.seconds(max(minutes, 0) * 60).formatted(.units(allowed: [.hours, .minutes], width: .wide))
    }

    // MARK: Phrases

    /// Widget, next event: "In 4m".
    static func startsIn(minutes: Int) -> String {
        let d = duration(minutes: minutes)
        return String(localized: "In \(d)", bundle: .module, comment: "Calendar widget: next event starts in a duration (\"In 4m\")")
    }
    /// The band, Meeting soon: "in 4m" (Russian: "4 мин" — no room for "через"). `compactLabel`, up to 30 minutes
    /// (the longest lead time): fits the 48u medium slot in both languages (tested).
    static func bandStartsIn(minutes: Int, language: CalendarLanguage = .app) -> String {
        let d = duration(minutes: minutes, language: language)
        return String(localized: "in \(d)", bundle: language.bundle, locale: language.locale,
                      comment: "Meeting soon, in the notch band: starts in a duration (\"in 4m\"); keep it as short as possible")
    }

    /// The band, Meeting in progress, time left: "−12m" / "−12 мин", "−1:30" from an hour on. A sign instead of
    /// "left", as the Media widget writes remaining time ("−2:11", DESIGN.md §7.1): "12m left" is 53 pt in
    /// `compact` and the medium slot holds 48. The full phrase is in the peek and VoiceOver.
    static func bandTimeLeft(minutes: Int, language: CalendarLanguage = .app) -> String {
        let d = bandDuration(minutes: minutes, language: language)
        return String(localized: "−\(d)", bundle: language.bundle, locale: language.locale,
                      comment: "Meeting in progress, in the notch band: time left with a minus sign (\"−12m\", \"−1:30\"); at most 48 pt")
    }

    /// The band, Meeting in progress, time elapsed: "+12m" / "+12 мин", "+1:30" from an hour on.
    static func bandTimeElapsed(minutes: Int, language: CalendarLanguage = .app) -> String {
        let d = bandDuration(minutes: minutes, language: language)
        return String(localized: "+\(d)", bundle: language.bundle, locale: language.locale,
                      comment: "Meeting in progress, in the notch band: time elapsed with a plus sign (\"+12m\", \"+1:30\"); at most 48 pt")
    }

    /// The smallest scale the band's meeting value may shrink to (Russian "−59 мин" needs 0.87; 13 pt → 11 pt,
    /// above the 10-pt floor of DESIGN.md §2.2). English never shrinks.
    static let bandMinimumScale: CGFloat = 0.85

    /// Minutes under an hour ("12m" / "12 мин"), then hours and minutes as "1:30": "1 ч 30 мин" is 69 pt.
    private static func bandDuration(minutes: Int, language: CalendarLanguage) -> String {
        let minutes = max(minutes, 0)
        guard minutes >= 60 else { return duration(minutes: minutes, language: language) }
        return Duration.seconds(minutes * 60).formatted(.time(pattern: .hourMinute).locale(language.locale))
    }
    /// Widget, live event: "Now · 12m left".
    static func nowWithTimeLeft(minutes: Int) -> String {
        let d = duration(minutes: minutes)
        return String(localized: "Now · \(d) left", bundle: .module, comment: "Calendar widget: the event in progress and the time left (\"Now · 12m left\")")
    }
    /// "12m left".
    static func timeLeft(minutes: Int) -> String { left(duration(minutes: minutes)) }
    /// "12m in" (time elapsed).
    static func timeElapsed(minutes: Int) -> String {
        let d = duration(minutes: minutes)
        return String(localized: "\(d) in", bundle: .module, comment: "Meeting in progress: time elapsed since the start (\"12m in\")")
    }
    /// The 2-cell widget's live event: "Now".
    static var now: String { String(localized: "Now", bundle: .module, comment: "Calendar widget: label for the event in progress") }
    static var allDay: String { String(localized: "All day", bundle: .module, comment: "Calendar widget: time column of an all-day event") }

    /// "Design review" or, for an untitled event, "Untitled event"; "Event" under Demo-mode redaction.
    static func title(_ event: EventSnapshot, redacted: Bool) -> String {
        if redacted { return String(localized: "Event", bundle: .module, comment: "Calendar: placeholder title shown instead of real titles in Demo mode") }
        if event.title.isEmpty { return String(localized: "Untitled event", bundle: .module, comment: "Calendar: an event without a title") }
        return event.title
    }

    /// Peek subtitle: "10:30–11:00 · Room 4" (no location under redaction, the service name for a link-only location).
    static func subtitle(_ event: EventSnapshot, link: MeetingLink?, redacted: Bool) -> String {
        let range = timeRange(event.start, event.end)
        let place = redacted ? nil : (event.readableLocation ?? link?.service.displayName)
        guard let place else { return range }
        return String(localized: "\(range) · \(place)", bundle: .module, comment: "Meeting peek: time range and place (\"10:30–11:00 · Room 4\")")
    }

    // MARK: VoiceOver

    static func spokenStartsIn(minutes: Int, at start: Date) -> String {
        let d = spokenDuration(minutes: minutes), t = time(start)
        return String(localized: "Starts in \(d), at \(t)", bundle: .module, comment: "VoiceOver: when a meeting starts (\"Starts in 4 minutes, at 10:30\")")
    }
    static func spokenTimeLeft(minutes: Int) -> String { left(spokenDuration(minutes: minutes)) }

    /// One key for "12m left" and "12 minutes left" (the duration is already spelled).
    private static func left(_ duration: String) -> String {
        String(localized: "\(duration) left", bundle: .module,
               comment: "Meeting in progress: time left; the argument is a duration (\"12m left\", VoiceOver \"12 minutes left\")")
    }
    static func spokenElapsed(minutes: Int) -> String {
        let d = spokenDuration(minutes: minutes)
        return String(localized: "\(d) elapsed", bundle: .module, comment: "VoiceOver: time since a meeting started (\"12 minutes elapsed\")")
    }
}
