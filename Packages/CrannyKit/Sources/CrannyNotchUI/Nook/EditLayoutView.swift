// CrannyNotchUI/Nook/EditLayoutView.swift — Edit layout (⌘E, DESIGN.md §6.6): cards get a dashed outline and
// an 8 × 24 resize handle on the trailing edge; they wiggle (Reduce Motion: a "–" badge instead). Drag a card
// to reorder (`listReorder`), drag the handle to resize in whole cells (an `.alignment` haptic and a "4 cells"
// tooltip per cell), ⌥← / ⌥→ move the focused card, ⌥⇧← / ⌥⇧→ resize it; every change is announced to
// VoiceOver and written through `NotchUIActions.commitLayout`. ↩ or Esc finishes (the header's Done).
import AppKit
import CrannyCore
import Foundation
import SwiftUI

struct EditLayoutView: View {
    @Environment(\.cranny) private var theme
    @FocusState private var focused: WidgetID?
    @State private var drag: CardDrag?
    @State private var resize: HandleDrag?
    let page: NookPage
    let model: NotchSceneModel
    let registry: ModuleRegistry
    let actions: NotchUIActions

    private struct CardDrag: Equatable {
        var widget: WidgetID
        var startX: CGFloat              // the card's x in the row when the drag began
        var translation: CGFloat
        var draft: [NookItem]
    }
    private struct HandleDrag: Equatable {
        var widget: WidgetID
        var startCells: Int
        var cells: Int
    }

    var body: some View {
        let items = drag?.draft ?? page.items
        HStack(spacing: theme.grid.gutter) {
            ForEach(Array(items.enumerated()), id: \.element.widget) { index, item in
                card(item, index: index, items: items)
            }
        }
        .animation(theme.animation(.listReorder), value: items)
        .onKeyPress(keys: [.leftArrow, .rightArrow], phases: .down) { press in
            keyboardEdit(press) ? .handled : .ignored
        }
        .onAppear { focused = model.open?.focus ?? page.items.first?.widget }
    }

    // MARK: Cards

    private func card(_ item: NookItem, index: Int, items: [NookItem]) -> some View {
        let isDragged = drag?.widget == item.widget
        let cells = registry.widget(item.widget)?.sizes.clamp(item.cells) ?? max(item.cells, 1)
        return WidgetCard(item: item, registry: registry, isEditing: true, isFocused: focused == item.widget,
                          commands: cardCommands)
            .overlay {
                RoundedRectangle(cornerRadius: theme.grid.cardRadius, style: .continuous)
                    .strokeBorder(theme.palette.stroke, style: StrokeStyle(lineWidth: StrokeWidth.emphasis, dash: StrokeWidth.dash))
                    .allowsHitTesting(false)
            }
            .overlay(alignment: .trailing) { handle(for: item, cells: cells) }
            .overlay(alignment: .topLeading) {
                if theme.reduceMotion { RemoveBadge { remove(item.widget) } }
            }
            .modifier(Wiggle(index: index, isActive: !theme.reduceMotion && !isDragged && resize == nil))
            .crannyElevation(Elevation.lifted, amount: isDragged ? 1 : 0)
            .offset(x: isDragged ? dragOffset(index: index, items: items) : 0)
            .zIndex(isDragged ? 1 : 0)
            .focusable()
            .focused($focused, equals: item.widget)
            .focusEffectDisabled()
            .gesture(reorderGesture(item.widget, index: index, items: items))
            .accessibilityAction(named: Text("Move left", bundle: .module, comment: "Layout editor: VoiceOver action")) {
                move(item.widget, by: -1)
            }
            .accessibilityAction(named: Text("Move right", bundle: .module, comment: "Layout editor: VoiceOver action")) {
                move(item.widget, by: 1)
            }
            .accessibilityAction(named: Text("Wider", bundle: .module, comment: "Layout editor: VoiceOver action, one cell wider")) {
                resize(item.widget, by: 1)
            }
            .accessibilityAction(named: Text("Narrower", bundle: .module, comment: "Layout editor: VoiceOver action, one cell narrower")) {
                resize(item.widget, by: -1)
            }
    }

    /// The 8 × 24 handle on the trailing edge, with the "4 cells" tooltip while it is dragged.
    private func handle(for item: NookItem, cells: Int) -> some View {
        let active = resize?.widget == item.widget
        return Capsule(style: .continuous)
            .fill(active ? theme.accentColor : theme.palette.secondaryLabel)
            .frame(width: 4, height: 18)
            .frame(width: 8, height: 24)
            .background(Capsule(style: .continuous).fill(theme.palette.surface.opacity(0.6)))
            .contentShape(Rectangle().inset(by: -6))
            .offset(x: 4)
            .overlay(alignment: .top) {
                if active {
                    CardStrings.cells(resize?.cells ?? cells)
                        .crannyFont(.caption)
                        .foregroundStyle(theme.palette.label)
                        .padding(.horizontal, Space.s).padding(.vertical, Space.xxs)
                        .background(Capsule(style: .continuous).fill(theme.palette.controlPressed))
                        .fixedSize()
                        .offset(y: -22)
                        .transition(.opacity)
                }
            }
            .onHover { inside in if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() } }
            .gesture(resizeGesture(item.widget, cells: cells))
            .accessibilityHidden(true)                    // VoiceOver: Wider / Narrower actions on the card
    }

    // MARK: Gestures

    private func reorderGesture(_ widget: WidgetID, index: Int, items: [NookItem]) -> some Gesture {
        // Measured in the canvas: the card itself moves (and reorders) under the pointer while it is dragged.
        DragGesture(minimumDistance: 4, coordinateSpace: .named(NotchCoordinateSpace.name))
            .onChanged { value in
                var current = drag ?? CardDrag(widget: widget, startX: rowX(of: index, in: items), translation: 0, draft: items)
                current.translation = value.translation.width
                let widths = current.draft.map { width(of: $0) }
                if let from = current.draft.firstIndex(where: { $0.widget == widget }) {
                    let start = rowX(of: from, in: current.draft)
                    let to = LayoutEditing.dropIndex(widths: widths, gutter: theme.grid.gutter, from: from,
                                                     translation: current.startX + current.translation - start)
                    if to != from {
                        let item = current.draft.remove(at: from)
                        current.draft.insert(item, at: to)
                        registry.services.haptics.play(.alignment)
                    }
                }
                drag = current
            }
            .onEnded { _ in
                guard let final = drag else { return }
                drag = nil
                if final.draft != page.items, let editing = editing() {
                    var next = editing
                    if let p = next.pages.firstIndex(where: { $0.id == page.id }) { next.pages[p].items = final.draft }
                    commit(next, announce: positionAnnouncement(widget, in: next))
                }
            }
    }

    private func resizeGesture(_ widget: WidgetID, cells: Int) -> some Gesture {
        // Measured in the canvas: the handle follows the card's trailing edge as it grows.
        DragGesture(minimumDistance: 1, coordinateSpace: .named(NotchCoordinateSpace.name))
            .onChanged { value in
                var current = resize ?? HandleDrag(widget: widget, startCells: cells, cells: cells)
                let target = current.startCells + LayoutEditing.cellDelta(translation: value.translation.width,
                                                                          cell: theme.grid.cell, gutter: theme.grid.gutter)
                if target != current.cells, let editing = editing(),
                   let index = editing.items.firstIndex(where: { $0.widget == widget }),
                   let next = editing.resizing(at: index, to: target, sizes: registry.widget(widget)?.sizes) {
                    current.cells = next.items[index].cells
                    actions.commitLayout(next.pages)                         // the shape follows live (`resize`)
                    registry.services.haptics.play(.alignment)
                }
                resize = current
            }
            .onEnded { _ in
                if let final = resize, final.cells != final.startCells {
                    announce(cellsAnnouncement(final.widget, cells: final.cells))
                }
                resize = nil
            }
    }

    private func dragOffset(index: Int, items: [NookItem]) -> CGFloat {
        guard let drag else { return 0 }
        return drag.startX + drag.translation - rowX(of: index, in: items)
    }

    // MARK: Keyboard and VoiceOver

    private func keyboardEdit(_ press: KeyPress) -> Bool {
        guard press.modifiers.contains(.option), let widget = focused else { return false }
        let step = press.key == .leftArrow ? -1 : 1
        if press.modifiers.contains(.shift) { resize(widget, by: step) } else { move(widget, by: step) }
        return true
    }

    private func move(_ widget: WidgetID, by step: Int) {
        guard let editing = editing(), let index = editing.items.firstIndex(where: { $0.widget == widget }),
              let next = editing.moving(from: index, to: index + step) else { return }
        commit(next, announce: positionAnnouncement(widget, in: next))
    }

    private func positionAnnouncement(_ widget: WidgetID, in editing: LayoutEditing) -> String {
        let position = (editing.items.firstIndex { $0.widget == widget } ?? 0) + 1
        return String(localized: "\(title(of: widget)), position \(position)", bundle: .module,
                      comment: "Layout editor: VoiceOver announcement after a move (widget name, new position)")
    }

    private func resize(_ widget: WidgetID, by step: Int) {
        guard let editing = editing(), let index = editing.items.firstIndex(where: { $0.widget == widget }) else { return }
        let sizes = registry.widget(widget)?.sizes
        let current = sizes?.clamp(editing.items[index].cells) ?? editing.items[index].cells
        guard let next = editing.resizing(at: index, to: current + step, sizes: sizes) else { return }
        registry.services.haptics.play(.alignment)
        commit(next, announce: cellsAnnouncement(widget, cells: next.items[index].cells))
    }

    private func remove(_ widget: WidgetID) {
        guard let next = editing()?.removing(widget) else { return }
        commit(next, announce: String(localized: "Removed \(title(of: widget))", bundle: .module,
                                      comment: "Layout editor: VoiceOver announcement after a widget was removed"))
    }

    private func commit(_ editing: LayoutEditing, announce message: String) {
        actions.commitLayout(editing.pages)
        announce(message)
    }

    private func announce(_ message: String) {
        AccessibilityNotification.Announcement(message).post()
    }

    private func cellsAnnouncement(_ widget: WidgetID, cells: Int) -> String {
        String(localized: "\(title(of: widget)), \(cells) cells", bundle: .module,
               comment: "Layout editor: VoiceOver announcement after a resize (widget name, width in cells)")
    }

    // MARK: Helpers

    private var cardCommands: CardCommands {
        var c = CardCommands()
        c.remove = { remove($0) }
        c.resize = { widget, cells in
            guard let editing = editing(), let index = editing.items.firstIndex(where: { $0.widget == widget }),
                  let next = editing.resizing(at: index, to: cells, sizes: registry.widget(widget)?.sizes) else { return }
            commit(next, announce: cellsAnnouncement(widget, cells: cells))
        }
        c.editLayout = {}
        return c
    }

    private func editing() -> LayoutEditing? {
        LayoutEditing(pages: registry.services.settings[CoreSettings.pages], pageID: page.id, maxColumns: model.layout.maxColumns)
    }

    private func width(of item: NookItem) -> CGFloat {
        theme.grid.width(cells: registry.widget(item.widget)?.sizes.clamp(item.cells) ?? max(item.cells, 1))
    }

    private func rowX(of index: Int, in items: [NookItem]) -> CGFloat {
        items.prefix(index).reduce(0) { $0 + width(of: $1) + theme.grid.gutter }
    }

    private func title(of widget: WidgetID) -> String {
        registry.widget(widget)?.title ?? WidgetPlaceholder(widget).title
    }
}

#Preview("Edit layout") {
    let (model, registry) = previewScene(.open, mode: .editLayout)
    NotchCanvasView(model: model, registry: registry)
        .frame(width: model.layout.canvasSize.width, height: 240)
        .background(Color(white: 0.25))
}
