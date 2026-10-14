// CrannyOnboarding/Support/WidgetCatalog.swift — names and glyphs of the widgets the presets use. A registered
// widget speaks for itself (`AnyNookWidget.title`/`symbol`); until its module is built, onboarding falls back to
// its own copy (DESIGN.md §14.1 symbols), so a preset never shows a raw id.
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

    static func fallback(_ id: WidgetID) -> WidgetInfo {
        switch id {
        case .media: WidgetInfo(title: String(localized: "Media", bundle: .module, comment: "Welcome, layouts: widget name"), symbol: "music.note")
        case .calendar: WidgetInfo(title: String(localized: "Calendar", bundle: .module, comment: "Welcome, layouts: widget name"), symbol: "calendar")
        case .quickApps: WidgetInfo(title: String(localized: "Quick Apps", bundle: .module, comment: "Welcome, layouts: widget name"), symbol: "app.dashed")
        case .mirror: WidgetInfo(title: String(localized: "Mirror", bundle: .module, comment: "Welcome, layouts: widget name (camera preview)"), symbol: "web.camera")
        case .notes: WidgetInfo(title: String(localized: "Notes", bundle: .module, comment: "Welcome, layouts: widget name"), symbol: "note.text")
        case .todos: WidgetInfo(title: String(localized: "To-dos", bundle: .module, comment: "Welcome, layouts: widget name"), symbol: "checklist")
        case .timer: WidgetInfo(title: String(localized: "Timer", bundle: .module, comment: "Welcome, layouts: widget name"), symbol: "timer")
        case .airDrop: WidgetInfo(title: "AirDrop", symbol: "dot.radiowaves.up.forward")
        case .files: WidgetInfo(title: String(localized: "Files", bundle: .module, comment: "Welcome, layouts: widget name"), symbol: "folder")
        default: WidgetInfo(title: id.rawValue, symbol: "app.dashed")
        }
    }
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
        case .listener: String(localized: "Music, your day and favorite apps", bundle: .module, comment: "Welcome, layouts: Listener preset description")
        case .maker: String(localized: "Notes, to-dos and a timer", bundle: .module, comment: "Welcome, layouts: Maker preset description")
        case .meetings: String(localized: "Your calendar, a camera check and a timer", bundle: .module, comment: "Welcome, layouts: Meetings preset description")
        case .minimal: String(localized: "Just music and the volume HUD", bundle: .module, comment: "Welcome, layouts: Minimal preset description")
        }
    }
}
