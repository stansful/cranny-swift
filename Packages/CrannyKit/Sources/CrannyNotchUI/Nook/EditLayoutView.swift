// CrannyNotchUI/Nook/EditLayoutView.swift — Edit layout (⌘E, DESIGN.md §6.6): cards get a dashed outline and
// an 8 × 24 resize handle on the trailing edge; they wiggle (Reduce Motion: a "–" badge instead). Drag a card
// to reorder (`listReorder`), drag the handle to resize in whole cells (an `.alignment` haptic and a "4 cells"
// tooltip per cell), ⌥← / ⌥→ move the focused card, ⌥⇧← / ⌥⇧→ resize it; every change is announced to
// VoiceOver and written through `NotchUIActions.commitLayout`. ↩ or Esc finishes (the header's Done). One
// `WiggleClock` drives every card's wiggle at the effect budget's rate. Right to left the row is mirrored: the pointer's
// travel is turned into travel along the row, and ⌥← / ⌥→ and Move left / right go the way they point. A drag event
// moves the dragged card's offset; the widgets inside the cards are not rebuilt (`WidgetCard.equatable()`).
import AppKit
import CrannyCore
import Foundation
import SwiftUI

struct EditLayoutView: View {
    @Environment(\.cranny) private var theme
    @Environment(\.layoutDirection) private var direction
    @FocusState private var focused: WidgetID?
    /// The card / handle whose drag is in flight. SwiftUI resets these when a gesture ends OR is cancelled, so
    /// the drafts below only count while their gesture is alive (a cancelled drag leaves nothing behind).
    @GestureState private var reordering: WidgetID?
    @GestureState private var resizing: WidgetID?
    @State private var drag: CardDrag?
    @State private var resize: HandleDrag?
    let page: NookPage
    let model: NotchSceneModel
    let registry: ModuleRegistry
    let actions: NotchUIActions

    private struct CardDrag: Equatable {
        var widget: WidgetID
        var origin: CGPoint              // where this drag began (a new drag never reuses an old draft)
        var startX: CGFloat              // the card's x in the row when the drag began
        var translation: CGFloat         // along the row (leading → trailing), not the pointer's physical travel
        var draft: [NookItem]
    }
    private struct HandleDrag: Equatable {
        var widget: WidgetID
        var origin: CGPoint
        var startCells: Int
        var cells: Int
    }

    /// The reorder in flight, if its gesture is still alive.
    private var activeDrag: CardDrag? { drag.flatMap { $0.widget == reordering ? $0 : nil } }
    /// The resize in flight, if its gesture is still alive.
    private var activeResize: HandleDrag? { resize.flatMap { $0.widget == resizing ? $0 : nil } }

    var body: some View {
        let items = activeDrag?.draft ?? page.items
        HStack(spacing: theme.grid.gutter) {
            ForEach(Array(items.enumerated()), id: \.element.widget) { index, item in
                card(item, index: index, items: items)
            }
        }
        .modifier(WiggleClock(interval: wiggleInterval))
        .animation(theme.animation(.listReorder), value: items)
        .onKeyPress(keys: [.leftArrow, .rightArrow], phases: .down) { press in
            keyboardEdit(press) ? .handled : .ignored
        }
        .onAppear { focused = model.open?.focus ?? page.items.first?.widget }
        .onDisappear { drag = nil; resize = nil }
    }

    /// The wiggle's frame interval from the effect budget (nil = paused: occluded, Low Power, full screen,
    /// Reduce Motion or Instant).
    private var wiggleInterval: Double? {
        registry.services.environment.effectBudget(
            isOpen: model.phase == .open, isOnScreen: model.isVisibleOnScreen,
            reduceMotion: theme.reduceMotion || theme.motion == .instant).minimumInterval
    }

    // MARK: Cards

    private func card(_ item: NookItem, index: Int, items: [NookItem]) -> some View {
        let isDragged = activeDrag?.widget == item.widget
        let cells = registry.widget(item.widget)?.sizes.clamp(item.cells) ?? max(item.cells, 1)
        return WidgetCard(item: item, registry: registry, isEditing: true, isFocused: focused == item.widget,
                          commands: cardCommands)
            .equatable()                                      // a drag event moves the card, it does not rebuild it
            .overlay {
                RoundedRectangle(cornerRadius: theme.grid.cardRadius, style: .continuous)
                    .strokeBorder(theme.palette.stroke, style: StrokeStyle(lineWidth: StrokeWidth.emphasis, dash: StrokeWidth.dash))
                    .allowsHitTesting(false)
            }
            .overlay(alignment: .trailing) { handle(for: item, cells: cells) }
            .overlay(alignment: .topLeading) {
                if theme.reduceMotion { RemoveBadge { remove(item.widget) } }
            }
            .modifier(Wiggle(index: index, isActive: !theme.reduceMotion && !isDragged && activeResize?.widget != item.widget))
            .crannyElevation(Elevation.lifted, amount: isDragged ? 1 : 0)
            .offset(x: isDragged ? dragOffset(index: index, items: items) : 0)
            .zIndex(isDragged ? 1 : 0)
            .focusable()
            .focused($focused, equals: item.widget)
            .focusEffectDisabled()
            .gesture(reorderGesture(item.widget, index: index, items: items))
            .accessibilityAction(named: Text("Move left", bundle: .module, comment: "Layout editor: VoiceOver action")) {
                move(item.widget, by: direction.step(physical: -1))
            }
            .accessibilityAction(named: Text("Move right", bundle: .module, comment: "Layout editor: VoiceOver action")) {
                move(item.widget, by: direction.step(physical: 1))
            }
            // Wider / Narrower: the card's own VoiceOver actions (CardAccessibilityActions), through cardCommands.
    }

    /// The 8 × 24 handle on the trailing edge, with the "4 cells" tooltip while it is dragged.
    private func handle(for item: NookItem, cells: Int) -> some View {
        let active = activeResize?.widget == item.widget
        let h = ResizeHandleMetrics.self
        return Capsule(style: .continuous)
            .fill(active ? theme.accentColor : theme.palette.secondaryLabel)
            .frame(width: h.grip.width, height: h.grip.height)
            .frame(width: h.size.width, height: h.size.height)
            .background(Capsule(style: .continuous).fill(theme.palette.scrim))   // legible over any card or light
            .contentShape(Rectangle().inset(by: -h.hitOutset))
            .offset(x: h.size.width / 2)                                            // straddles the card's edge
            .overlay(alignment: .top) {
                if active {
                    CardStrings.cells(activeResize?.cells ?? cells)
                        .crannyFont(.caption)
                        .foregroundStyle(theme.palette.label)
                        .padding(.horizontal, Space.s).padding(.vertical, Space.xxs)
                        .background(Capsule(style: .continuous).fill(theme.palette.controlPressed))
                        .fixedSize()
                        .offset(y: -h.tooltipLift)
                        .transition(.opacity)
                }
            }
            .modifier(ResizeCursor())
            .gesture(resizeGesture(item.widget, cells: cells))
            .accessibilityHidden(true)                    // VoiceOver: Wider / Narrower actions on the card
    }

    // MARK: Gestures

    private func reorderGesture(_ widget: WidgetID, index: Int, items: [NookItem]) -> some Gesture {
        // Measured in the canvas: the card itself moves (and reorders) under the pointer while it is dragged.
        DragGesture(minimumDistance: 4, coordinateSpace: .named(NotchCoordinateSpace.name))
            .updating($reordering) { _, state, _ in state = widget }
            .onChanged { value in
                var current = drag.flatMap { $0.widget == widget && $0.origin == value.startLocation ? $0 : nil }
                    ?? CardDrag(widget: widget, origin: value.startLocation, startX: rowX(of: index, in: items),
                                translation: 0, draft: items)
                current.translation = direction.alongLayout(value.translation.width)
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
                guard let final = drag, final.widget == widget else { return }
                drag = nil
                if final.draft != page.items {
                    var next = editing()
                    if let p = next.pages.firstIndex(where: { $0.id == page.id }) { next.pages[p].items = final.draft }
                    let position = (final.draft.firstIndex { $0.widget == widget } ?? 0) + 1
                    commit(next, announce: LayoutAnnouncement.moved(title(of: widget), position: position))
                }
            }
    }

    private func resizeGesture(_ widget: WidgetID, cells: Int) -> some Gesture {
        // Measured in the canvas: the handle follows the card's trailing edge as it grows.
        DragGesture(minimumDistance: 1, coordinateSpace: .named(NotchCoordinateSpace.name))
            .updating($resizing) { _, state, _ in state = widget }
            .onChanged { value in
                var current = resize.flatMap { $0.widget == widget && $0.origin == value.startLocation ? $0 : nil }
                    ?? HandleDrag(widget: widget, origin: value.startLocation, startCells: cells, cells: cells)
                // The handle is on the trailing edge: right to left, dragging it left widens the card.
                let target = current.startCells + LayoutEditing.cellDelta(translation: direction.alongLayout(value.translation.width),
                                                                          cell: theme.grid.cell, gutter: theme.grid.gutter)
                let rules = editing()
                if target != current.cells, let index = rules.items.firstIndex(where: { $0.widget == widget }),
                   let next = rules.resizing(at: index, to: target) {
                    current.cells = next.items[index].cells
                    actions.commitLayout(next.pages)                         // the shape follows live (`resize`)
                    registry.services.haptics.play(.alignment)
                }
                resize = current
            }
            .onEnded { _ in
                if let final = resize, final.widget == widget, final.cells != final.startCells {
                    LayoutAnnouncement.post(LayoutAnnouncement.resized(title(of: final.widget), cells: final.cells))
                }
                resize = nil
            }
    }

    private func dragOffset(index: Int, items: [NookItem]) -> CGFloat {
        guard let drag = activeDrag else { return 0 }
        return drag.startX + drag.translation - rowX(of: index, in: items)
    }

    // MARK: Keyboard and VoiceOver

    private func keyboardEdit(_ press: KeyPress) -> Bool {
        guard press.modifiers.contains(.option), let widget = focused, let step = direction.step(for: press.key) else { return false }
        if press.modifiers.contains(.shift) { resize(widget, by: step) } else { move(widget, by: step) }
        return true
    }

    private func move(_ widget: WidgetID, by step: Int) {
        let rules = editing()
        guard let index = rules.items.firstIndex(where: { $0.widget == widget }),
              let next = rules.moving(from: index, to: index + step) else { return }
        let position = (next.items.firstIndex { $0.widget == widget } ?? 0) + 1
        commit(next, announce: LayoutAnnouncement.moved(title(of: widget), position: position))
    }

    private func resize(_ widget: WidgetID, by step: Int) {
        let rules = editing()
        guard let index = rules.items.firstIndex(where: { $0.widget == widget }) else { return }
        resize(widget, to: rules.cells(of: rules.items[index]) + step)
    }

    /// ⌥⇧← / ⌥⇧→, the card's Wider / Narrower VoiceOver actions: one step, a haptic, the new width announced.
    private func resize(_ widget: WidgetID, to cells: Int) {
        let rules = editing()
        guard let index = rules.items.firstIndex(where: { $0.widget == widget }),
              let next = rules.resizing(at: index, to: cells) else { return }
        registry.services.haptics.play(.alignment)
        commit(next, announce: LayoutAnnouncement.resized(title(of: widget), cells: next.cells(of: next.items[index])))
    }

    private func remove(_ widget: WidgetID) {
        guard let next = editing().removing(widget) else { return }
        commit(next, announce: LayoutAnnouncement.removed(title(of: widget)))
    }

    private func commit(_ editing: LayoutEditing, announce message: String) {
        actions.commitLayout(editing.pages)
        LayoutAnnouncement.post(message)
    }

    // MARK: Helpers

    /// The card's ⋯ commands while editing (VoiceOver actions; the hover menu is hidden in the editor). They use only
    /// the page's id, the scene, the registry and the actions, and read the pages when they run (`CardCommands`).
    private var cardCommands: CardCommands {
        var c = CardCommands(page: page.id)
        c.remove = { remove($0) }
        c.resize = { widget, cells in resize(widget, to: cells) }
        c.allowedSizes = { editing().allowedSizes(for: $0) }
        c.editLayout = {}
        return c
    }

    private func editing() -> LayoutEditing {
        LayoutEditing(pages: registry.services.settings[CoreSettings.pages], pageID: page.id,
                      maxColumns: model.layout.maxColumns, registry: registry)
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

/// The resize handle (DESIGN.md §6.6: 8 × 24 on the trailing edge).
private enum ResizeHandleMetrics {
    static let size = CGSize(width: 8, height: 24)
    /// The visible grip inside it.
    static let grip = CGSize(width: 4, height: 18)
    /// How far the drag target reaches beyond it (≥ 20 × 36: easy to grab without covering the card).
    static let hitOutset: CGFloat = 6
    /// The "4 cells" tooltip sits this far above the handle's top.
    static let tooltipLift: CGFloat = 22
}

/// The column-resize pointer over the handle. macOS 15+: `pointerStyle`, which SwiftUI resets by itself.
/// macOS 14: `NSCursor` push/pop, balanced on disappear, because SwiftUI sends no hover-out when a hovered view
/// goes away (Done, Esc, the card removed, the panel closing) and the resize cursor would stick.
private struct ResizeCursor: ViewModifier {
    @State private var pushed = false

    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content.pointerStyle(.columnResize)
        } else {
            content
                .onHover { inside in
                    if inside, !pushed {
                        NSCursor.resizeLeftRight.push()
                        pushed = true
                    } else if !inside, pushed {
                        NSCursor.pop()
                        pushed = false
                    }
                }
                .onDisappear {
                    if pushed { NSCursor.pop(); pushed = false }
                }
        }
    }
}

#Preview("Edit layout") {
    let (model, registry) = previewScene(.open, mode: .editLayout)
    NotchCanvasView(model: model, registry: registry)
        .frame(width: model.layout.canvasSize.width, height: 240)
        .background(Color(white: 0.25))
}
