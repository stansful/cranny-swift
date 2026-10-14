// CrannyHUD/HUDSettings.swift — the module's settings keys (namespace `hud`, ARCHITECTURE.md §10.10) and the
// public value type they use. Settings ▸ HUD shows every key (DESIGN.md §11.1); "Reset HUD…" resets them all.
import CrannyCore
import Foundation

/// Settings ▸ HUD ▸ Colors (DESIGN.md §10): the fill of the level bar.
public nonisolated enum HUDColors: String, Codable, CaseIterable, Sendable {
    /// White, the default: the HUD stays neutral like the system one.
    case mono
    /// The resolved accent for every kind.
    case accent
    /// Accent for volume, `caution` (yellow) for brightness, `info` (blue) for the keyboard.
    case semantic
}

/// Keys of the HUD module. Defaults follow ARCHITECTURE.md §10.10, except `brightness` (see its comment).
public nonisolated enum HUDSettings {
    /// Replace the system volume/brightness HUD. Needs Accessibility (the key tap); off by default, and without
    /// it Cranny draws no HUD at all — never two HUDs (ARCHITECTURE.md D10).
    public static let replaceSystemHUD = SettingKey<Bool>(.hud, "replaceSystemHUD", default: false)
    /// Handle the volume and mute keys.
    public static let volume = SettingKey<Bool>(.hud, "volume", default: true)
    /// Handle the brightness keys of the built-in display. Off by default until the hardware checklist confirms
    /// that real brightness keys on Apple Silicon arrive as `NX_KEYTYPE_BRIGHTNESS_*` and DisplayServices sets
    /// the built-in panel (ARCHITECTURE.md §7.1, §10.10 acceptance, §11.2 item 6). Flip the default then.
    public static let brightness = SettingKey<Bool>(.hud, "brightness", default: false)
    /// Handle the keyboard backlight keys (older and external keyboards; Apple Silicon keyboards have none).
    public static let keyboardBacklight = SettingKey<Bool>(.hud, "keyboardBacklight", default: true)
    /// The level bar's fill.
    public static let colors = SettingKey<HUDColors>(.hud, "colors", default: .mono)
    /// Show the level as a number ("62") before the glyph. Always shown under Differentiate Without Color.
    public static let showsValue = SettingKey<Bool>(.hud, "showsValue", default: false)
    /// After the default output device changes, the next volume HUD shows that device's glyph.
    public static let showsOutputDevice = SettingKey<Bool>(.hud, "showsOutputDevice", default: true)
    /// Seconds the HUD stays after the last change (0.8–3, DESIGN.md §10).
    public static let duration = SettingKey<Double>(.hud, "duration", default: HoverIntent.hudAutoDismiss)

    /// The range of `duration` offered in Settings ▸ HUD.
    public static let durationRange: ClosedRange<Double> = 0.8...3
    /// `duration`, clamped to `durationRange` (a hand-edited default cannot keep the HUD forever).
    static func clampedDuration(_ seconds: Double) -> Double {
        min(max(seconds, durationRange.lowerBound), durationRange.upperBound)
    }
}
