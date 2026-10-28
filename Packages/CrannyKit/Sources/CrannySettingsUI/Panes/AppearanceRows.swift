// CrannySettingsUI/Panes/AppearanceRows.swift — the rows of Settings ▸ Appearance (DESIGN.md §11.1), shared by the
// pane (labels) and the search index (labels + localized keywords).
import CrannyCore
import Foundation

enum AppearanceRows {
    static var accent: SettingsRowInfo {
        SettingsRowInfo(.appearance, "accent",
                        title: String(localized: "Accent", bundle: .module, comment: "Settings ▸ Appearance: accent colour picker"),
                        keywords: [String(localized: "color", bundle: .module, comment: "Settings search: keyword for Accent")])
    }
    static var textSize: SettingsRowInfo {
        SettingsRowInfo(.appearance, "textSize",
                        title: String(localized: "Text size", bundle: .module, comment: "Settings ▸ Appearance: picker"),
                        keywords: [String(localized: "font", bundle: .module, comment: "Settings search: keyword for Text size")])
    }
    static var motion: SettingsRowInfo {
        SettingsRowInfo(.appearance, "motion",
                        title: String(localized: "Motion", bundle: .module, comment: "Settings ▸ Appearance: picker Calm / Standard / Lively / Instant"),
                        keywords: [String(localized: "animation", bundle: .module, comment: "Settings search: keyword for Motion"),
                                   String(localized: "bounce", bundle: .module, comment: "Settings search: keyword for Motion")])
    }
    static var typingEffect: SettingsRowInfo {
        SettingsRowInfo(.appearance, "typingEffect",
                        title: String(localized: "Typing effect", bundle: .module, comment: "Settings ▸ Appearance: toggle"))
    }
    static var ambience: SettingsRowInfo {
        SettingsRowInfo(.appearance, "ambience",
                        title: String(localized: "Ambient light", bundle: .module, comment: "Settings ▸ Appearance: picker Off / Subtle / Vivid"),
                        keywords: [String(localized: "glow", bundle: .module, comment: "Settings search: keyword for Ambient light")])
    }
    static var effect: SettingsRowInfo {
        SettingsRowInfo(.appearance, "effect",
                        title: String(localized: "Effect", bundle: .module, comment: "Settings ▸ Appearance: picker Aurora / Motes / Tide"),
                        keywords: [String(localized: "aurora", bundle: .module, comment: "Settings search: keyword for the light effect")])
    }
    /// Searchable by its options too: the README and the footnote name the setting "Quality ▸ Efficient".
    static var ambientDetail: SettingsRowInfo {
        SettingsRowInfo(.appearance, "ambientDetail",
                        title: String(localized: "Quality", bundle: .module, comment: "Settings ▸ Appearance: picker Detailed / Efficient (how the ambient light is drawn)"),
                        keywords: [String(localized: "memory", bundle: .module, comment: "Settings search: keyword for the light's Quality (Efficient uses less memory)"),
                                   String(localized: "performance", bundle: .module, comment: "Settings search: keyword for the light's Quality"),
                                   detailedLabel, efficientLabel])
    }
    /// Quality's options, shared by the pane's picker and the row's search keywords.
    static var detailedLabel: String {
        String(localized: "Detailed", bundle: .module, comment: "Settings ▸ Appearance ▸ Quality: option (the default, the full light)")
    }
    static var efficientLabel: String {
        String(localized: "Efficient", bundle: .module, comment: "Settings ▸ Appearance ▸ Quality: option (a simpler light that uses much less memory)")
    }
    static var albumGlow: SettingsRowInfo {
        SettingsRowInfo(.appearance, "albumGlow",
                        title: String(localized: "Album glow", bundle: .module, comment: "Settings ▸ Appearance: toggle"))
    }
    static var underglow: SettingsRowInfo {
        SettingsRowInfo(.appearance, "underglow",
                        title: String(localized: "Underglow", bundle: .module, comment: "Settings ▸ Appearance: toggle (light below the open panel)"))
    }
    static var progressRim: SettingsRowInfo {
        SettingsRowInfo(.appearance, "progressRim",
                        title: String(localized: "Progress rim", bundle: .module, comment: "Settings ▸ Appearance: toggle"))
    }
    static var translucent: SettingsRowInfo {
        SettingsRowInfo(.appearance, "translucentBackground",
                        title: String(localized: "Translucent background", bundle: .module, comment: "Settings ▸ Appearance: toggle"),
                        keywords: [String(localized: "transparency", bundle: .module, comment: "Settings search: keyword for Translucent background")])
    }
    static var glassIsland: SettingsRowInfo {
        SettingsRowInfo(.appearance, "glassIsland",
                        title: String(localized: "Glass island", bundle: .module, comment: "Settings ▸ Appearance: toggle (Liquid Glass, macOS 26+)"),
                        keywords: [String(localized: "Liquid Glass", bundle: .module, comment: "Settings search: keyword for Glass island")])
    }
    static var buttons: SettingsRowInfo {
        SettingsRowInfo(.appearance, "buttonShape",
                        title: String(localized: "Buttons", bundle: .module, comment: "Settings ▸ Appearance: picker Capsule / Rounded"))
    }
    static var widgets: SettingsRowInfo {
        SettingsRowInfo(.appearance, "widgetStyle",
                        title: String(localized: "Widgets", bundle: .module, comment: "Settings ▸ Appearance: picker Cards / Flat"))
    }
    static var density: SettingsRowInfo {
        SettingsRowInfo(.appearance, "density",
                        title: String(localized: "Density", bundle: .module, comment: "Settings ▸ Appearance: picker Compact / Standard / Roomy"))
    }
    static var panelPadding: SettingsRowInfo {
        SettingsRowInfo(.appearance, "panelPadding",
                        title: String(localized: "Panel padding", bundle: .module, comment: "Settings ▸ Appearance: slider ±4 pt"))
    }
    static var notchFitWidth: SettingsRowInfo {
        SettingsRowInfo(.appearance, "notchFitWidth",
                        title: String(localized: "Notch width", bundle: .module, comment: "Settings ▸ Appearance ▸ Notch fit: slider ±10 pt"),
                        keywords: [String(localized: "calibrate", bundle: .module, comment: "Settings search: keyword for Notch fit")])
    }
    static var notchFitRadius: SettingsRowInfo {
        SettingsRowInfo(.appearance, "notchFitRadius",
                        title: String(localized: "Corner radius", bundle: .module, comment: "Settings ▸ Appearance ▸ Notch fit: slider ±3 pt"))
    }
    static var noNotchStyle: SettingsRowInfo {
        SettingsRowInfo(.appearance, "noNotchStyle",
                        title: String(localized: "On displays without a notch", bundle: .module, comment: "Settings ▸ Appearance: picker Floating island / Attached / Off"),
                        keywords: [String(localized: "external monitor", bundle: .module, comment: "Settings search: keyword for the display settings")])
    }
    static var handle: SettingsRowInfo {
        SettingsRowInfo(.appearance, "handle",
                        title: String(localized: "Handle", bundle: .module, comment: "Settings ▸ Appearance: picker Visible / Hidden until hover (no-notch displays)"))
    }

    /// The rows the pane shows on this system: Glass island exists only on macOS 26 and later, so search never
    /// offers a row that is not there.
    static var all: [SettingsRowInfo] {
        rows(includingGlassIsland: hasGlassIsland)
    }

    /// Whether this system has Liquid Glass (the Glass island row).
    static var hasGlassIsland: Bool {
        if #available(macOS 26.0, *) { true } else { false }
    }

    static func rows(includingGlassIsland: Bool) -> [SettingsRowInfo] {
        [accent, textSize, motion, typingEffect, ambience, effect, ambientDetail, albumGlow, underglow, progressRim, translucent]
            + (includingGlassIsland ? [glassIsland] : [])
            + [buttons, widgets, density, panelPadding, notchFitWidth, notchFitRadius, noNotchStyle, handle]
    }
}
