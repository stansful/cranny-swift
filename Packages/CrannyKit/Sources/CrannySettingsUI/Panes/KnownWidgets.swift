// CrannySettingsUI/Panes/KnownWidgets.swift — what Layout & Widgets shows for a widget: the registry's values, or, for
// an ID no module registered (left in a saved layout), the raw identifier, a placeholder glyph and generic sizes.
// Previews and tests that want real names register Core's stand-ins (`ModuleRegistry.addPreviewStandIns()`).
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
    /// The registered widget's values, else a generic placeholder.
    static func info(_ id: WidgetID, registry: ModuleRegistry) -> WidgetInfo {
        if let widget = registry.widget(id) {
            return WidgetInfo(id: id, title: widget.title, symbol: widget.symbol, summary: widget.summary, sizes: widget.sizes, isRegistered: true,
                              hasOptions: widget.hasOptions)
        }
        return WidgetInfo(id: id, title: id.rawValue, symbol: "app.dashed", summary: nil,
                          sizes: WidgetSizes(minimum: 1, preferred: 2, maximum: 8), isRegistered: false, hasOptions: false)
    }
}
