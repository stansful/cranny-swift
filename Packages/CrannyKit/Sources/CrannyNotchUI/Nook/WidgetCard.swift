// CrannyNotchUI/Nook/WidgetCard.swift — the card chrome around a widget's content (DESIGN.md §6.8), and a
// placeholder card for widgets whose module is not built yet. WP0 skeleton: card, hover fill, VoiceOver
// container. WP12 adds the ⋯ overflow menu, focus sections and the "Widgets" rotor.
import CrannyCore
import Foundation
import SwiftUI

struct WidgetCard: View {
    @Environment(\.cranny) private var theme
    @State private var hovered = false
    let item: NookItem
    let registry: ModuleRegistry
    let context: NotchContext

    var body: some View {
        let grid = theme.grid
        if let widget = registry.widget(item.widget) {
            let cells = widget.sizes.clamp(item.cells)
            let inset = widget.isFrameless ? 0 : grid.density.cardPadding
            widget.makeBody(context: WidgetContext(
                cells: cells, rows: grid.rows,
                contentSize: CGSize(width: grid.width(cells: cells) - 2 * inset, height: grid.height - 2 * inset),
                isFocused: context.focusedWidget == widget.id, isPreview: context.isPreview,
                redactsPersonalData: context.redactsPersonalData))
                .crannyCard(cells: cells, hovered: hovered, frameless: widget.isFrameless)
                .onHover { hovered = $0 }
                .accessibilityElement(children: .contain)
                .accessibilityLabel(Text(verbatim: widget.title))
        } else {
            let placeholder = WidgetPlaceholder(item.widget)
            VStack(spacing: Space.s) {
                Image(systemName: placeholder.symbol).font(.system(size: 20, weight: .medium))
                Text(verbatim: placeholder.title).crannyFont(.caption).lineLimit(2).multilineTextAlignment(.center)
            }
            .foregroundStyle(theme.palette.tertiaryLabel)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .crannyCard(cells: max(item.cells, 1), hovered: hovered)
            .onHover { hovered = $0 }
            .accessibilityElement(children: .combine)
        }
    }
}

/// Name and glyph of a well-known widget, shown until its module registers it (DESIGN.md §14.1 symbols).
struct WidgetPlaceholder {
    let title: String
    let symbol: String

    init(_ id: WidgetID) {
        switch id {
        case .media: (title, symbol) = (String(localized: "Media", bundle: .module, comment: "Widget placeholder name"), "music.note")
        case .calendar: (title, symbol) = (String(localized: "Calendar", bundle: .module, comment: "Widget placeholder name"), "calendar")
        case .quickApps: (title, symbol) = (String(localized: "Quick Apps", bundle: .module, comment: "Widget placeholder name"), "app.dashed")
        case .mirror: (title, symbol) = (String(localized: "Mirror", bundle: .module, comment: "Widget placeholder name"), "web.camera")
        case .notes: (title, symbol) = (String(localized: "Notes", bundle: .module, comment: "Widget placeholder name"), "note.text")
        case .todos: (title, symbol) = (String(localized: "To-dos", bundle: .module, comment: "Widget placeholder name"), "checklist")
        case .timer: (title, symbol) = (String(localized: "Timer", bundle: .module, comment: "Widget placeholder name"), "timer")
        case .airDrop: (title, symbol) = ("AirDrop", "dot.radiowaves.up.forward")
        case .files: (title, symbol) = (String(localized: "Files", bundle: .module, comment: "Widget placeholder name"), "folder")
        default: (title, symbol) = (id.rawValue, "app.dashed")
        }
    }
}

#Preview("Placeholder cards") {
    let (model, registry) = previewScene(.open)
    HStack(spacing: Space.s) {
        WidgetCard(item: NookItem(.media, cells: 4), registry: registry, context: model.context)
        WidgetCard(item: NookItem(.timer, cells: 2), registry: registry, context: model.context)
    }
    .padding(Space.l)
    .background(.black)
    .crannyThemeRoot(CrannyTheme())
}
