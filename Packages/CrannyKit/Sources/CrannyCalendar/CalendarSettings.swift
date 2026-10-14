// CrannyCalendar/CalendarSettings.swift — the module's settings keys (namespace `calendar.`, ARCHITECTURE.md
// §10.3) and the public value types they use. Raw values are persisted: never rename one.
import CrannyCore
import Foundation

/// Settings of the Calendar widget and the meeting activities. Shown in Settings ▸ Calendar, in the widget's
/// options popover and under the meeting rows of Settings ▸ Live Activities.
public nonisolated enum CalendarSettings {
    /// Days before today the widget can page back to (0–7).
    public static let daysBehind = SettingKey<Int>(.calendar, "daysBehind", default: 0)
    /// Days after today the widget can page forward to (0–7). Tomorrow's first event fills the empty state.
    public static let daysAhead = SettingKey<Int>(.calendar, "daysAhead", default: 1)
    /// Today's ended events stay in the list, dimmed and struck through.
    public static let showsPastEventsToday = SettingKey<Bool>(.calendar, "showsPastEventsToday", default: true)
    /// `EKCalendar.calendarIdentifier`s the user unchecked.
    public static let hiddenCalendarIDs = SettingKey<[String]>(.calendar, "hiddenCalendarIDs", default: [])
    public static let includesAllDay = SettingKey<Bool>(.calendar, "includesAllDay", default: true)
    public static let includesBirthdays = SettingKey<Bool>(.calendar, "includesBirthdays", default: false)
    /// Minutes before a meeting that "Meeting soon" appears (1–30). A second alert follows at one minute.
    public static let leadMinutes = SettingKey<Int>(.calendar, "leadMinutes", default: 5)
    /// What "Meeting in progress" counts: time left (default) or time elapsed.
    public static let inEventDisplay = SettingKey<InEventDisplay>(.calendar, "inEventDisplay", default: .remaining)
    /// Services whose links get a Join button.
    public static let joinProviders = SettingKey<[MeetingService]>(.calendar, "joinProviders", default: MeetingService.allCases)
    /// Open meetings in the service's app when it is installed; otherwise (or when off) in the browser.
    public static let joinsInApp = SettingKey<Bool>(.calendar, "joinsInApp", default: true)

    /// Allowed range of `daysBehind` / `daysAhead` (DESIGN.md §7.2 day strip: 0–7 each).
    static let dayRange = 0...7
    /// Allowed range of `leadMinutes` (DESIGN.md §11.1).
    static let leadRange = 1...30
}

/// Settings ▸ Live Activities ▸ Meeting in progress ▸ Show.
public nonisolated enum InEventDisplay: String, Codable, CaseIterable, Sendable {
    case remaining
    case elapsed
}

/// A video-meeting service whose links Cranny recognises (ARCHITECTURE.md §7.4).
public nonisolated enum MeetingService: String, Codable, CaseIterable, Sendable {
    case zoom, meet, teams, webex, facetime, slack, whereby, goto, jitsi, chime

    /// The product name, shown as is in every language.
    public var displayName: String {
        switch self {
        case .zoom: "Zoom"
        case .meet: "Google Meet"
        case .teams: "Microsoft Teams"
        case .webex: "Webex"
        case .facetime: "FaceTime"
        case .slack: "Slack"
        case .whereby: "Whereby"
        case .goto: "GoTo Meeting"
        case .jitsi: "Jitsi Meet"
        case .chime: "Amazon Chime"
        }
    }
}
