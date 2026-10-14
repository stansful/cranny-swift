// CrannyTimer/UI/TimerCopy.swift — every user-visible string of the module, in one place so a key keeps ONE
// comment (ARCHITECTURE.md §10.0 "Surface: purpose"). Keys are the English text; Russian lives in the catalog.
import Foundation

nonisolated enum TimerCopy {
    // MARK: Names

    static var timer: String {
        String(localized: "Timer", bundle: .module, comment: "Timer: module name (widget, live activity, ⌘K result kind)")
    }
    static var timerDone: String {
        String(localized: "Timer done", bundle: .module, comment: "Timer done: activity name and peek title (Live Activities pane, peek row, VoiceOver)")
    }
    static var summary: String {
        String(localized: "Countdowns with presets", bundle: .module, comment: "Widget library: Timer description")
    }

    // MARK: States

    static func ends(at time: String) -> String {
        String(localized: "Ends \(time)", bundle: .module, comment: "Timer: end time of a running timer, e.g. “Ends 14:35” (widget ring, peek row)")
    }
    static var paused: String {
        String(localized: "Paused", bundle: .module, comment: "Timer: state of a paused timer (widget ring, peek row)")
    }
    static var done: String {
        String(localized: "Done", bundle: .module, comment: "Timer done: short label in the band next to the timer glyph (≤ 6 characters)")
    }

    // MARK: Actions

    static var start: String {
        String(localized: "Start", bundle: .module, comment: "Timer widget: button that starts the duration shown in the ring")
    }
    static var pause: String {
        String(localized: "Pause timer", bundle: .module, comment: "Timer: pause button and VoiceOver/⌘K action")
    }
    static var resume: String {
        String(localized: "Resume timer", bundle: .module, comment: "Timer: resume button and VoiceOver/⌘K action")
    }
    static var stop: String {
        String(localized: "Stop timer", bundle: .module, comment: "Timer: stop button and VoiceOver/⌘K action")
    }
    static var stopShort: String {
        String(localized: "Stop", bundle: .module, comment: "Timer done: peek button that silences and clears the finished timer")
    }
    static var addMinute: String {
        String(localized: "Add 1 minute", bundle: .module, comment: "Timer: VoiceOver/⌘K action and tooltip of the +1 min button")
    }
    static var plusOneMinute: String {
        String(localized: "+1 min", bundle: .module, comment: "Timer: button that adds one minute (peek row, widget); keep it short")
    }
    static var startShortcut: String {
        String(localized: "Start timer", bundle: .module, comment: "Settings ▸ Keyboard: shortcut name")
    }
    static func startMinutes(_ minutes: Int) -> String {
        String(localized: "Start \(minutes)-minute timer", bundle: .module, comment: "Command palette and preset chips (VoiceOver): starts a timer of whole minutes")
    }
    static func startDuration(_ duration: String) -> String {
        String(localized: "Start timer for \(duration)", bundle: .module, comment: "Command palette and preset chips (VoiceOver): starts a timer, e.g. “Start timer for 1m 30s”")
    }
    /// "Start 5-minute timer" / "Start timer for 1m 30s" (⌘K, preset tooltips and VoiceOver).
    static func startTitle(seconds: Int) -> String {
        seconds % 60 == 0 ? startMinutes(seconds / 60) : startDuration(TimerFormat.short(seconds))
    }
    static var commandKeywords: [String] {
        [timer, String(localized: "Countdown", bundle: .module, comment: "Command palette: search keyword for Timer commands")]
    }

    // MARK: Widget set-up

    static func unit(_ unit: TimerFormat.PresetUnit) -> String {
        switch unit {
        case .hours: String(localized: "hr", bundle: .module, comment: "Timer widget: unit under a preset number, hours (shown uppercase, ≤ 4 letters)")
        case .minutes: String(localized: "min", bundle: .module, comment: "Timer widget: unit under a preset number, minutes (shown uppercase, ≤ 4 letters)")
        case .seconds: String(localized: "sec", bundle: .module, comment: "Timer widget: unit under a preset number, seconds (shown uppercase, ≤ 4 letters)")
        case .clock: ""
        }
    }
    static var typingHint: String {
        String(localized: "25 or 90s", bundle: .module, comment: "Timer widget: example formats under a typed entry that is not a duration yet (fits under the digits)")
    }

    // MARK: VoiceOver

    static var runningLabel: String {
        String(localized: "Timer running", bundle: .module, comment: "Timer activity: VoiceOver label")
    }
    static var pausedLabel: String {
        String(localized: "Timer paused", bundle: .module, comment: "Timer activity: VoiceOver label of a paused timer")
    }
    static func left(_ spoken: String) -> String {
        String(localized: "\(spoken) left", bundle: .module, comment: "Timer: VoiceOver value, time left, e.g. “4 minutes, 59 seconds left”")
    }
    static func left(_ spoken: String, endingAt time: String) -> String {
        String(localized: "\(spoken) left, ends \(time)", bundle: .module, comment: "Timer widget: VoiceOver value of a running timer, e.g. “4 minutes, 59 seconds left, ends 14:35”")
    }
    static func pausedLeft(_ spoken: String) -> String {
        String(localized: "Paused, \(spoken) left", bundle: .module, comment: "Timer: VoiceOver value of a paused timer, e.g. “Paused, 2 minutes left”")
    }
    static func setUp(_ spoken: String) -> String {
        String(localized: "Set to \(spoken)", bundle: .module, comment: "Timer widget: VoiceOver value of the idle ring, the duration Return starts")
    }
    static var choosePreset: String {
        String(localized: "Choose a duration", bundle: .module, comment: "Timer widget: VoiceOver value when the presets are shown")
    }

    // MARK: Options

    static var peekOption: String {
        String(localized: "Peek at one minute left", bundle: .module, comment: "Live Activities pane: timer option")
    }
    static var presetsTitle: String {
        String(localized: "Presets", bundle: .module, comment: "Timer options: section title of the four preset durations")
    }
    static func presetLabel(_ index: Int) -> String {
        String(localized: "Preset \(index)", bundle: .module, comment: "Timer options: row label of one preset, e.g. “Preset 1”")
    }
    static var soundTitle: String {
        String(localized: "Sound when done", bundle: .module, comment: "Timer options: picker of the system alert sound")
    }
    static var noSound: String {
        String(localized: "None", bundle: .module, comment: "Timer options: sound picker entry for no sound")
    }

    /// The name System Settings ▸ Sound shows for one of `TimerSettings.systemSounds` (a file name, which is what
    /// the setting stores and `NSSound(named:)` plays). Since macOS 14 they differ: "Glass" is Crystal / Кристалл.
    /// The keys are those English names and the catalog has Apple's Russian ones. A name that is not one of the
    /// system sounds (written outside the picker) shows as stored.
    static func soundName(_ fileName: String) -> String {
        switch fileName {
        case "Basso": String(localized: "Mezzo", bundle: .module, comment: "Timer options: macOS alert sound name (match System Settings ▸ Sound)")
        case "Blow": String(localized: "Breeze", bundle: .module, comment: "Timer options: macOS alert sound name (match System Settings ▸ Sound)")
        case "Bottle": String(localized: "Pebble", bundle: .module, comment: "Timer options: macOS alert sound name (match System Settings ▸ Sound)")
        case "Frog": String(localized: "Jump", bundle: .module, comment: "Timer options: macOS alert sound name (match System Settings ▸ Sound)")
        case "Funk": String(localized: "Funky", bundle: .module, comment: "Timer options: macOS alert sound name (match System Settings ▸ Sound)")
        case "Glass": String(localized: "Crystal", bundle: .module, comment: "Timer options: macOS alert sound name (match System Settings ▸ Sound)")
        case "Hero": String(localized: "Heroine", bundle: .module, comment: "Timer options: macOS alert sound name (match System Settings ▸ Sound)")
        case "Morse": String(localized: "Pong", bundle: .module, comment: "Timer options: macOS alert sound name (match System Settings ▸ Sound)")
        case "Ping": String(localized: "Sonar", bundle: .module, comment: "Timer options: macOS alert sound name (match System Settings ▸ Sound)")
        case "Pop": String(localized: "Bubble", bundle: .module, comment: "Timer options: macOS alert sound name (match System Settings ▸ Sound)")
        case "Purr": String(localized: "Pluck", bundle: .module, comment: "Timer options: macOS alert sound name (match System Settings ▸ Sound)")
        case "Sosumi": String(localized: "Sonumi", bundle: .module, comment: "Timer options: macOS alert sound name (match System Settings ▸ Sound)")
        case "Submarine": String(localized: "Submerge", bundle: .module, comment: "Timer options: macOS alert sound name (match System Settings ▸ Sound)")
        case "Tink": String(localized: "Boop", bundle: .module, comment: "Timer options: macOS alert sound name (match System Settings ▸ Sound)")
        default: fileName
        }
    }
}
