// CrannyTimer/TimerSettings.swift — the module's settings keys (ARCHITECTURE.md §10.8). Stored as
// `cranny.timer.<name>`; never rename one. Timer STATE is content, not settings: `AppPaths/timer/state.json`.
import CrannyCore

/// Settings of the Timer module. Shown in the Timer widget's options (Layout & Widgets) and, for the peek option,
/// under Timer in Settings ▸ Live Activities.
public enum TimerSettings {
    /// Preset durations in SECONDS, in display order (widget chips, ⌘K). At most `maximumPresets` are shown.
    public static let presets = SettingKey<[Int]>(.timer, "presets", default: [60, 300, 600, 1500])
    /// The system alert sound played when a timer finishes (`NSSound(named:)`); nil = no sound. Muted in Demo mode.
    public static let sound = SettingKey<String?>(.timer, "sound", default: "Glass")
    /// Peek the running timer when one minute is left.
    public static let peeksAtOneMinute = SettingKey<Bool>(.timer, "peeksAtOneMinute", default: true)

    /// The widget shows four preset chips (a 2 × 2 grid, or a column at 3 cells).
    public static let maximumPresets = 4

    /// The classic macOS alert sounds in /System/Library/Sounds, offered by the sound picker. Names are what
    /// `NSSound(named:)` resolves; they are proper names and are shown untranslated.
    public static let systemSounds = ["Basso", "Blow", "Bottle", "Frog", "Funk", "Glass", "Hero", "Morse",
                                      "Ping", "Pop", "Purr", "Sosumi", "Submarine", "Tink"]
}
