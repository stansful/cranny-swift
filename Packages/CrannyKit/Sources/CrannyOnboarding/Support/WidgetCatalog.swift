// CrannyOnboarding/Support/WidgetCatalog.swift — names and glyphs of the widgets the presets use: a registered widget
// speaks for itself (`AnyNookWidget.title`/`symbol`). The app registers every widget; an ID nobody registered shows its
// raw identifier and a placeholder glyph. Previews register Core's stand-ins (`ModuleRegistry.addPreviewStandIns()`).
import CrannyCore
import Foundation

struct WidgetInfo: Equatable {
    let title: String
    let symbol: String
}

@MainActor enum WidgetCatalog {
    static func info(_ id: WidgetID, in registry: ModuleRegistry) -> WidgetInfo {
        if let widget = registry.widget(id) { return WidgetInfo(title: widget.title, symbol: widget.symbol) }
        return fallback(id)
    }

    static func fallback(_ id: WidgetID) -> WidgetInfo { WidgetInfo(title: id.rawValue, symbol: "app.dashed") }
}

/// Copy for the four starting layouts (DESIGN.md §12.1 step 4).
extension NookPreset {
    var title: String {
        switch self {
        case .listener: String(localized: "Listener", bundle: .module, comment: "Welcome, layouts: preset name (Media, Calendar, Apps)")
        case .maker: String(localized: "Maker", bundle: .module, comment: "Welcome, layouts: preset name (Notes, To-dos, Timer, Shortcuts)")
        case .meetings: String(localized: "Meetings", bundle: .module, comment: "Welcome, layouts: preset name (Calendar, Mirror, Timer, Apps)")
        case .minimal: String(localized: "Minimal", bundle: .module, comment: "Welcome, layouts: preset name (Media only, plus the HUD)")
        }
    }

    /// One short line under the name.
    var summary: String {
        switch self {
        case .listener: String(localized: "Music, your day and favourite apps", bundle: .module, comment: "Welcome, layouts: Listener preset description")
        case .maker: String(localized: "Notes, to-dos and a timer", bundle: .module, comment: "Welcome, layouts: Maker preset description")
        case .meetings: String(localized: "Your calendar, a camera check and a timer", bundle: .module, comment: "Welcome, layouts: Meetings preset description")
        case .minimal: String(localized: "Just music and the volume HUD", bundle: .module, comment: "Welcome, layouts: Minimal preset description")
        }
    }
}
