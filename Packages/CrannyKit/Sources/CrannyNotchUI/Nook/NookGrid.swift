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
    @Environment(\.notchEntrance) private var entrance
    @Namespace private var rotor
    @FocusState private var focused: WidgetID?
    @AccessibilityFocusState private var voiceOverFocus: WidgetID?
    let page: NookPage
    let model: NotchSceneModel
    let registry: ModuleRegistry
    let actions: NotchUIActions

    var body: some View {
        let items = page.items
        let rings = Stagger.rings(cells: items.map { cells(of: $0) })
        let entering = NotchEntrance.isEntering(entrance)
        HStack(spacing: theme.grid.gutter) {
            ForEach(Array(items.enumerated()), id: \.element.widget) { index, item in
                WidgetCard(item: item, registry: registry, isFocused: focused == item.widget,
                           commands: GridCommands.make(page: page, model: model, registry: registry, actions: actions))
                    .equatable()                                      // a grid update rebuilds only changed cards
                    .modifier(VoiceOverLanding(focus: $voiceOverFocus, widget: item.widget))
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
        .onAppear {
            focused = model.open?.focus
            // Opening puts VoiceOver on the widget the panel opened for, else the first one (DESIGN.md §16). Only
            // when the panel opens: after a tab switch VoiceOver stays on the tab the user chose.
            if let target = WidgetGridPage.voiceOverTarget(entrance: entering, focus: model.open?.focus, items: items) {
                Task { @MainActor in voiceOverFocus = target }
            }
        }
        .onChange(of: model.open?.focus) { _, focus in if let focus { focused = focus } }
        .onChange(of: focused) { _, widget in actions.focusWidget(widget) }
    }

    private func cells(of item: NookItem) -> Int {
        registry.widget(item.widget)?.sizes.clamp(item.cells) ?? max(item.cells, 1)
    }

    /// Where VoiceOver lands when the panel opens on this page (nil: leave it where it is). Pure.
    nonisolated static func voiceOverTarget(entrance: Bool, focus: WidgetID?, items: [NookItem]) -> WidgetID? {
        guard entrance else { return nil }
        if let focus, items.contains(where: { $0.widget == focus }) { return focus }
        return items.first?.widget
    }
}

/// Binds a card to the page's VoiceOver focus, so opening can put VoiceOver on it (DESIGN.md §16). Snapshots
/// (`ImageRenderer`: tests, the gallery, `--qa-snapshot`) leave the binding out, because ImageRenderer draws
/// nothing for a view that carries one; `notchRendersFinalState` never changes within a live hierarchy, so this
/// switch never re-creates a card.
private struct VoiceOverLanding: ViewModifier {
    @Environment(\.notchRendersFinalState) private var isSnapshot
    let focus: AccessibilityFocusState<WidgetID?>.Binding
    let widget: WidgetID

    func body(content: Content) -> some View {
        if isSnapshot {
            content
        } else {
            content.accessibilityFocused(focus, equals: widget)
        }
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
                .padding(.vertical, FlatDivider.inset)
                .offset(x: (theme.grid.gutter + width) / 2)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    /// Inset at the top and bottom of the card row (DESIGN.md §6.3).
    static let inset: CGFloat = 10
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

/// The ⋯ menu's commands on a grid page, written through `commitLayout` / `setMode`. They capture the page's id,
/// the scene, the registry and the actions, and read the pages when they run (`CardCommands`).
enum GridCommands {
    @MainActor static func make(page: NookPage, model: NotchSceneModel, registry: ModuleRegistry,
                                actions: NotchUIActions) -> CardCommands {
        let pageID = page.id
        func editing() -> LayoutEditing {
            LayoutEditing(pages: registry.services.settings[CoreSettings.pages], pageID: pageID,
                          maxColumns: model.layout.maxColumns, registry: registry)
        }
        func title(_ widget: WidgetID) -> String { registry.widget(widget)?.title ?? WidgetPlaceholder(widget).title }
        var c = CardCommands(page: pageID)
        c.remove = { widget in
            guard let next = editing().removing(widget) else { return }
            actions.commitLayout(next.pages)
            LayoutAnnouncement.post(LayoutAnnouncement.removed(title(widget)))
        }
        c.resize = { widget, cells in
            let e = editing()
            guard let index = e.items.firstIndex(where: { $0.widget == widget }),
                  let next = e.resizing(at: index, to: cells) else { return }
            actions.commitLayout(next.pages)
            LayoutAnnouncement.post(LayoutAnnouncement.resized(title(widget), cells: next.cells(of: next.items[index])))
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
