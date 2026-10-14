// CrannyNotchUI/Nook/NookGrid.swift — a grid page (DESIGN.md §6.3): one row of cards, 2 rows tall, centred
// under the camera. Widgets enter radiating outward from the camera (18 ms per ring); Tab / ⇧Tab move between
// widgets (each card is a focus section); a "Widgets" VoiceOver rotor jumps between them; Notes focus shows one
// widget at all columns × 3 rows, growing out of its card with matched geometry.
import CrannyCore
import Foundation
import SwiftUI

struct WidgetGridPage: View {
    @Environment(\.cranny) private var theme
    @Environment(\.notchContext) private var context
    @Namespace private var rotor
    @FocusState private var focused: WidgetID?
    let page: NookPage
    let model: NotchSceneModel
    let registry: ModuleRegistry
    let actions: NotchUIActions

    var body: some View {
        let items = page.items
        let rings = Stagger.rings(cells: items.map { cells(of: $0) })
        HStack(spacing: theme.grid.gutter) {
            ForEach(Array(items.enumerated()), id: \.element.widget) { index, item in
                WidgetCard(item: item, registry: registry, isFocused: focused == item.widget,
                           commands: GridCommands.make(page: page, model: model, registry: registry, actions: actions))
                    .notchMatched("card.\(item.widget.rawValue)")
                    .focusable()
                    .focused($focused, equals: item.widget)
                    .focusEffectDisabled()
                    .focusSection()
                    .accessibilityRotorEntry(id: item.widget, in: rotor)
                    .overlay(alignment: .trailing) { if index < items.count - 1 { FlatDivider() } }
                    .staggeredReveal(delay: Stagger.delay(ring: rings[index], reduceMotion: theme.reduceMotion))
            }
        }
        .accessibilityRotor(Text("Widgets", bundle: .module, comment: "Open panel: VoiceOver rotor that jumps between widgets")) {
            ForEach(items, id: \.widget) { item in
                AccessibilityRotorEntry(Text(verbatim: registry.widget(item.widget)?.title ?? WidgetPlaceholder(item.widget).title),
                                        id: item.widget, in: rotor)
            }
        }
        .onAppear { focused = model.open?.focus }
        .onChange(of: model.open?.focus) { _, focus in if let focus { focused = focus } }
        .onChange(of: focused) { _, widget in actions.focusWidget(widget) }
    }

    private func cells(of item: NookItem) -> Int {
        registry.widget(item.widget)?.sizes.clamp(item.cells) ?? max(item.cells, 1)
    }
}

/// Flat widget style (DESIGN.md §6.3): a 1-px `hairline` divider in the middle of the doubled gutter, inset
/// 10 pt at the top and bottom. Drawn on a card's trailing side; cards style draws nothing.
private struct FlatDivider: View {
    @Environment(\.cranny) private var theme
    @Environment(\.displayScale) private var displayScale
    var body: some View {
        if theme.widgetStyle == .flat {
            let width = StrokeWidth.hairline(displayScale)
            Rectangle().fill(theme.palette.hairline)
                .frame(width: width)
                .padding(.vertical, 10)
                .offset(x: (theme.grid.gutter + width) / 2)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

/// Notes focus (DESIGN.md §7.5): one widget at all columns × 3 rows; the other widgets left with `contentOut`.
struct FocusedWidgetPage: View {
    let widget: WidgetID
    let model: NotchSceneModel
    let registry: ModuleRegistry

    var body: some View {
        WidgetCard(item: NookItem(widget, cells: model.layout.maxColumns), registry: registry, rows: 3, isFocused: true,
                   clampsToSizes: false)
            .notchMatched("card.\(widget.rawValue)")
    }
}

/// The ⋯ menu's commands on a grid page, written through `commitLayout` / `setMode`.
enum GridCommands {
    @MainActor static func make(page: NookPage, model: NotchSceneModel, registry: ModuleRegistry,
                                actions: NotchUIActions) -> CardCommands {
        func editing() -> LayoutEditing {
            LayoutEditing(pages: registry.services.settings[CoreSettings.pages], pageID: page.id,
                          maxColumns: model.layout.maxColumns, registry: registry)
        }
        var c = CardCommands()
        c.remove = { widget in if let next = editing().removing(widget) { actions.commitLayout(next.pages) } }
        c.resize = { widget, cells in
            let e = editing()
            guard let index = e.items.firstIndex(where: { $0.widget == widget }),
                  let next = e.resizing(at: index, to: cells) else { return }
            actions.commitLayout(next.pages)
        }
        c.editLayout = { actions.setMode(.editLayout) }
        c.allowedSizes = { widget in editing().allowedSizes(for: widget) }
        return c
    }
}

#Preview("Grid · Home") {
    let (model, registry) = previewScene(.open)
    NotchCanvasView(model: model, registry: registry)
        .frame(width: model.layout.canvasSize.width, height: 240)
        .background(Color(white: 0.25))
}

#Preview("Notes focus · 3 rows") {
    let (model, registry) = previewScene(.open, mode: .focus(.notes))
    NotchCanvasView(model: model, registry: registry)
        .frame(width: model.layout.canvasSize.width, height: 300)
        .background(Color(white: 0.25))
}
