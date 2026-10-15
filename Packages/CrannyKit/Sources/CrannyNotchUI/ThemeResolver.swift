// CrannyNotchUI/ThemeResolver.swift — CoreSettings → theme, layout and light palette.
// Shared by the shell (one per display), the Settings preview stage and the onboarding stage,
// so all three render identically. Pure functions of their inputs.
import AppKit
import CrannyCore
import SwiftUI

/// `CoreSettings` → theme, per-display layout, display keys and the light palette: one implementation for the
/// shell, the Settings stage and the onboarding stage, which cannot import each other.
public enum ThemeResolver {
    /// The theme of one surface. `albumAccent` = `services.nowPlaying?.palette?.accent` while media plays.
    public static func theme(settings: SettingsStore, albumAccent: RGB?, notchUnit: CGFloat,
                             isFloatingDisplay: Bool) -> CrannyTheme {
        theme(settings: settings, albumAccent: albumAccent, notchUnit: notchUnit, isFloatingDisplay: isFloatingDisplay,
              systemAccent: AccentResolver.systemAccent())
    }

    /// The theme of one surface with the system accent already read (`AccentResolver.systemAccent()`), so a caller
    /// that also needs it for the light palette (`ambientPalette`) reads the appearance once per evaluation.
    public static func theme(settings: SettingsStore, albumAccent: RGB?, notchUnit: CGFloat,
                             isFloatingDisplay: Bool, systemAccent: RGB) -> CrannyTheme {
        var t = CrannyTheme()
        t.textSize = settings[CoreSettings.textSize]
        t.density = settings[CoreSettings.density]
        t.widgetStyle = settings[CoreSettings.widgetStyle]
        t.buttonShape = settings[CoreSettings.buttonShape]
        t.motion = settings[CoreSettings.motion]
        t.ambience = settings[CoreSettings.ambience]
        t.effect = settings[CoreSettings.effect]
        t.ambientDetail = ambientDetail(settings: settings)
        t.translucentBackground = settings[CoreSettings.translucentBackground]
        t.panelPaddingTune = CGFloat(settings[CoreSettings.panelPaddingTune])
        t.glassIsland = isFloatingDisplay && settings[CoreSettings.glassIsland]
        t.hapticsEnabled = settings[CoreSettings.haptics]
        t.notchUnit = notchUnit
        t.accent = AccentResolver.resolve(settings[CoreSettings.accent], albumAccent: albumAccent,
                                          systemAccent: systemAccent, palette: t.palette.spec, increaseContrast: false)
        return t
    }

    /// Appearance ▸ Ambient light ▸ Quality: the Metal light (Detailed, the default) or the Core Animation light
    /// (Efficient). A Debug build launched with `-CrannyQAAmbientDetail efficient` (or `detailed`) uses that instead of
    /// the setting, for capture and energy runs (docs/CONTRIBUTING.md ▸ Effects); Release builds always read the setting.
    public static func ambientDetail(settings: SettingsStore) -> AmbientDetail {
        #if DEBUG
        if let raw = UserDefaults.standard.string(forKey: qaAmbientDetailKey), let detail = AmbientDetail(rawValue: raw) {
            return detail
        }
        #endif
        return settings[CoreSettings.ambientDetail]
    }

    /// The Debug QA switch of `ambientDetail(settings:)`.
    static let qaAmbientDetailKey = "CrannyQAAmbientDetail"

    /// Per-display layout. `metrics` come from `NotchMetrics.measure(screen)` (or `.reference` on a stage).
    public static func layout(metrics: NotchMetrics, displayModel: String?, style: NoNotchStyle,
                              settings: SettingsStore, textSize: CrannyTextSize, density: NookDensity,
                              widgetStyle: WidgetStyle) -> NotchLayout {
        let fit = displayModel.flatMap { settings[CoreSettings.notchFit][$0] } ?? NotchFit()
        return NotchLayout(metrics: metrics, noNotchStyle: style, widthTune: fit.widthTune, radiusTune: fit.radiusTune,
                           grid: NookGrid(density: density, textSize: textSize, style: widgetStyle,
                                          paddingTune: CGFloat(settings[CoreSettings.panelPaddingTune])))
    }

    /// `CGDisplayCreateUUIDFromDisplayID` string — the per-display settings key (stable across reconnects).
    public static func displayKey(_ screen: NSScreen) -> DisplayKey? {
        guard let n = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
              let uuid = CGDisplayCreateUUIDFromDisplayID(n.uint32Value)?.takeRetainedValue(),
              let string = CFUUIDCreateString(nil, uuid) as String? else { return nil }
        return DisplayKey(string)
    }

    /// "<vendor>-<model>" key of `CoreSettings.notchFit` (stable per display model, not per unit).
    public static func displayModelKey(_ screen: NSScreen) -> String? {
        guard let n = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
        let id = CGDirectDisplayID(n.uint32Value)
        return "\(CGDisplayVendorNumber(id))-\(CGDisplayModelNumber(id))"
    }

    /// The light-layer palette (DESIGN.md §5.2): the top activity's palette, else by accent source.
    public static func ambientPalette(topActivity: AmbientPalette?, accent: AccentSource, systemAccent: RGB) -> AmbientPalette {
        if let topActivity { return topActivity }
        switch accent {
        case .automatic, .system: return .tinted(systemAccent)
        case .swatch: return .afterglow
        case .monochrome: return .mono
        }
    }
}
