// CrannySettingsUI/Panes/KnownWidgets.swift — names, glyphs and sizes of the well-known widgets (DESIGN.md §6.7, §14.1),
// used by Layout & Widgets for a widget whose module has not registered it (yet): the registry's own values win.
import CrannyCore
import Foundation

/// What the layout editor shows for a widget.
struct WidgetInfo {
    let id: WidgetID
    let title: String
    let symbol: String
    let summary: String?
    let sizes: WidgetSizes
    /// The widget is registered (it can be added from the library).
    let isRegistered: Bool
    /// The widget offers options (`NookWidget.makeOptions()`).
    let hasOptions: Bool
}

enum KnownWidgets {
    /// The registered widget's values, else the design's table, else a generic placeholder.
    static func info(_ id: WidgetID, registry: ModuleRegistry) -> WidgetInfo {
        if let widget = registry.widget(id) {
            return WidgetInfo(id: id, title: widget.title, symbol: widget.symbol, summary: widget.summary, sizes: widget.sizes, isRegistered: true,
                              hasOptions: widget.hasOptions)
        }
        let known = table[id]
        return WidgetInfo(id: id, title: known?.title ?? id.rawValue, symbol: known?.symbol ?? "app.dashed", summary: nil,
                          sizes: known?.sizes ?? WidgetSizes(minimum: 1, preferred: 2, maximum: 8), isRegistered: false,
                          hasOptions: false)
    }

    /// DESIGN.md §6.7 sizes and §14.1 glyphs.
    static var table: [WidgetID: (title: String, symbol: String, sizes: WidgetSizes)] {
        [
            .media: (String(localized: "Media", bundle: .module, comment: "Settings: the Media feature (widget, pane)"), "music.note",
                     WidgetSizes(minimum: 4, preferred: 5, maximum: 6)),
            .calendar: (String(localized: "Calendar", bundle: .module, comment: "Settings: the Calendar feature (glossary: Календарь)"), "calendar",
                        WidgetSizes(minimum: 2, preferred: 3, maximum: 5)),
            .quickApps: (String(localized: "Quick Apps", bundle: .module, comment: "Settings: the Quick Apps widget (glossary: Быстрые приложения)"), "app.dashed",
                         WidgetSizes(minimum: 1, preferred: 2, maximum: 6)),
            .mirror: (String(localized: "Mirror", bundle: .module, comment: "Settings: the Mirror widget (glossary: Зеркало)"), "web.camera",
                      WidgetSizes(minimum: 2, preferred: 2, maximum: 3)),
            .notes: (String(localized: "Notes", bundle: .module, comment: "Settings: the Notes feature (glossary: Заметки)"), "note.text",
                     WidgetSizes(minimum: 3, preferred: 4, maximum: 8)),
            .todos: (String(localized: "To-dos", bundle: .module, comment: "Settings: the To-dos feature (glossary: Задачи)"), "checklist",
                     WidgetSizes(minimum: 2, preferred: 3, maximum: 6)),
            .timer: (String(localized: "Timer", bundle: .module, comment: "Settings: the Timer feature (widget, Simulate chip; glossary: Таймер)"), "timer",
                     WidgetSizes(minimum: 2, preferred: 2, maximum: 3)),
            .airDrop: ("AirDrop", "dot.radiowaves.up.forward", WidgetSizes(minimum: 1, preferred: 2, maximum: 2)),
            .files: (String(localized: "Files", bundle: .module, comment: "Settings: the Files widget (mini shelf of the Tray)"), "folder",
                     WidgetSizes(minimum: 3, preferred: 4, maximum: 8)),
        ]
    }
}
