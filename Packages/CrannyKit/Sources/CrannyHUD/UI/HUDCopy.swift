// CrannyHUD/UI/HUDCopy.swift — every user-visible HUD string that depends on the kind or the level, in one
// place (DESIGN.md §10, §16, §17). Numbers go through FormatStyle; whole sentences are single catalog keys.
import Foundation

nonisolated extension HUDKind {
    /// "Volume" — VoiceOver label of the HUD and the peek row title.
    var title: String {
        switch self {
        case .volume: String(localized: "Volume", bundle: .module, comment: "HUD: what the HUD shows (VoiceOver label, peek title, Settings ▸ HUD toggle)")
        case .brightness: String(localized: "Brightness", bundle: .module, comment: "HUD: what the HUD shows (VoiceOver label, peek title, Settings ▸ HUD toggle)")
        case .keyboardBacklight: String(localized: "Keyboard brightness", bundle: .module, comment: "HUD: what the HUD shows for the keyboard backlight keys (VoiceOver label, peek title)")
        }
    }

    /// The SF Symbol (DESIGN.md §14.1) for this kind at `level`.
    func symbol(level: Double, muted: Bool) -> String {
        switch self {
        case .volume: muted ? "speaker.slash.fill" : "speaker.wave.3.fill"
        case .brightness: level < 0.5 ? "sun.min.fill" : "sun.max.fill"
        case .keyboardBacklight: level <= 0 ? "light.min" : "light.max"     // light.min is too faint to carry a level
        }
    }

    /// `speaker.wave.3.fill` fills its waves with the level (variable value); the others have none.
    func variableValue(level: Double, muted: Bool) -> Double? {
        self == .volume && !muted ? LevelStepper.clamp(level) : nil
    }
}

nonisolated extension HUDDisplay {
    /// The glyph the HUD draws. Mute wins over an output-device glyph: `speaker.slash.fill` is how the HUD says
    /// "muted" (DESIGN.md §10), and under Differentiate Without Color the bar's colour must not be the only sign (§16).
    var symbolName: String {
        isMuted ? kind.symbol(level: level, muted: true) : deviceGlyph ?? kind.symbol(level: level, muted: false)
    }

    /// The speaker's waves fill with the level; device glyphs, the muted speaker and the other kinds have none.
    var symbolVariableValue: Double? {
        deviceGlyph == nil || isMuted ? kind.variableValue(level: level, muted: isMuted) : nil
    }
}

nonisolated enum HUDCopy {
    /// "62 %" in the user's locale.
    static func percentText(_ level: Double) -> String {
        (Double(LevelStepper.percent(level)) / 100).formatted(.percent.precision(.fractionLength(0)))
    }

    /// The accessibility value of the HUD activity: the level, or "Muted".
    static func accessibilityValue(_ display: HUDDisplay) -> String {
        display.isMuted
            ? String(localized: "Muted", bundle: .module, comment: "HUD: VoiceOver value and peek subtitle while the output is muted")
            : percentText(display.level)
    }

    /// Posted to VoiceOver once the value settles (DESIGN.md §16): "Volume, 62 %".
    static func announcement(_ display: HUDDisplay) -> String {
        let percent = percentText(display.level)
        return switch display.kind {
        case .volume where display.isMuted:
            String(localized: "Volume, muted", bundle: .module, comment: "HUD: VoiceOver announcement after the mute key")
        case .volume:
            String(localized: "Volume, \(percent)", bundle: .module, comment: "HUD: VoiceOver announcement once the level settles; argument is a percentage")
        case .brightness:
            String(localized: "Brightness, \(percent)", bundle: .module, comment: "HUD: VoiceOver announcement once the level settles; argument is a percentage")
        case .keyboardBacklight:
            String(localized: "Keyboard brightness, \(percent)", bundle: .module, comment: "HUD: VoiceOver announcement once the level settles; argument is a percentage")
        }
    }
}
