// CrannySettingsUI/Panes/GridEditor.swift — the WYSIWYG grid editor of Layout & Widgets (DESIGN.md §6.6, §18.7): the
// page's widgets as cards at their true proportions on a black panel (the notch's own tokens and theme), with the
// edit-mode look (dashed outline, 8 × 24 resize handle). Drag a card to reorder, drag its handle to resize in whole
// cells (an `.alignment` detent per cell and an "N cells" tip), "+" opens the widget library. Keyboard: ⌥← ⌥→ move,
// ⌥⇧← ⌥⇧→ resize; VoiceOver: named actions and an adjustable width; every change is announced.
import AppKit
import CrannyCore
import Foundation
import SwiftUI

struct GridEditor: View {
    let page: NookPage
    let editor: LayoutEditor
    let registry: ModuleRegistry
    let theme: CrannyTheme
    /// Commits a changed layout, or reports why a change was refused.
    let apply: LayoutCommit
    let showOptions: (WidgetID) -> Void
    @State private var showsLibrary = false

    var body: some View {
        let grid = theme.grid
        GeometryReader { proxy in
            let metrics = EditorMetrics(width: proxy.size.width, maxColumns: editor.maxColumns,
                                        usedCells: editor.usedCells(on: page.id), grid: grid)
            HStack(spacing: metrics.gutter) {
                ForEach(page.items, id: \.widget) { item in
                    EditorCard(info: KnownWidgets.info(item.widget, registry: registry),
                               cells: editor.cells(of: item.widget, on: page.id) ?? item.cells,
                               metrics: metrics, haptics: registry.services.haptics,
                               apply: apply, pageID: page.id, showOptions: showOptions)
                }
                AddTile(cellsLeft: editor.cellsLeft(on: page.id), width: metrics.addTile, height: metrics.cardHeight) { showsLibrary = true }
                    .popover(isPresented: $showsLibrary, arrowEdge: .bottom) {
                        WidgetLibraryList(registry: registry, page: page, editor: editor, apply: apply, compact: true)
                            .frame(width: 320, height: 300)
                    }
                Spacer(minLength: 0)
            }
            .frame(height: metrics.cardHeight)
        }
        .frame(height: EditorMetrics.cardHeight)
        .padding(EditorMetrics.panelPadding)
        .background(theme.palette.surface, in: RoundedRectangle(cornerRadius: grid.panelRadius * 0.75, style: .continuous))
        .crannyThemeRoot(theme)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Layout of \(LayoutRows.title(of: page))", bundle: .module,
                                 comment: "Settings ▸ Layout & Widgets: VoiceOver label of the grid editor; the argument is the page name"))
    }
}

/// Card geometry scaled so the whole row fits the editor's width: the cards and, after one gutter, the "+" tile. On a
/// page with free cells the tile takes them, so the row is exactly the page's maximum columns. On a full page (or one
/// that is over after a Text size or Density change) the tile keeps a fixed width and the cards shrink to make room,
/// so nothing pokes out of the panel.
struct EditorMetrics {
    static let cardHeight: CGFloat = 76
    static let panelPadding: CGFloat = 12
    /// The "+" tile when no cell is free.
    static let fullPageAddTile: CGFloat = HitTarget.preferred
    let cell: CGFloat
    let gutter: CGFloat
    /// Width of the "+" tile.
    let addTile: CGFloat

    init(width: CGFloat, maxColumns: Int, usedCells: Int, grid: NookGrid) {
        let columns = max(maxColumns, usedCells, 1)
        let cellsLeft = maxColumns - usedCells
        let reserved = cellsLeft > 0 ? 0 : Self.fullPageAddTile
        let full = grid.width(cells: columns) + (cellsLeft > 0 ? 0 : grid.gutter)
        let scale = full > 0 ? max(width - reserved, 1) / full : 1
        cell = grid.cell * scale
        gutter = grid.gutter * scale
        addTile = cellsLeft > 0 ? CGFloat(cellsLeft) * cell + CGFloat(cellsLeft - 1) * gutter : reserved
    }

    var cardHeight: CGFloat { Self.cardHeight }
    func width(cells: Int) -> CGFloat { CGFloat(cells) * cell + CGFloat(max(cells - 1, 0)) * gutter }

    /// The laid-out row: cards of `cards` cells with a gutter after each, then the "+" tile.
    func rowWidth(cards: [Int]) -> CGFloat {
        cards.reduce(0) { $0 + width(cells: $1) + gutter } + addTile
    }
}

/// One widget in edit mode.
private struct EditorCard: View {
    @Environment(\.cranny) private var theme
    let info: WidgetInfo
    let cells: Int
    let metrics: EditorMetrics
    let haptics: Haptics
    let apply: LayoutCommit
    let pageID: PageID
    let showOptions: (WidgetID) -> Void
    @State private var dragCells: Int?
    @State private var isTargeted = false
    @FocusState private var focused: Bool

    var body: some View {
        let shown = dragCells ?? cells
        let p = theme.palette
        VStack(spacing: Space.xs) {
            Image(systemName: info.symbol).font(.system(size: 16, weight: .medium)).foregroundStyle(p.secondaryLabel)
            Text(verbatim: info.title).crannyFont(.caption).foregroundStyle(p.label)
                .lineLimit(2).multilineTextAlignment(.center).minimumScaleFactor(0.85)
            Text(verbatim: LayoutRows.cells(shown)).crannyFont(.caption).foregroundStyle(p.tertiaryLabel).lineLimit(1)
        }
        .padding(.leading, Space.xs)
        .padding(.trailing, Space.m + Space.s)                 // clear of the resize handle
        .frame(width: metrics.width(cells: shown), height: metrics.cardHeight)
        .background(RoundedRectangle(cornerRadius: Radius.tile, style: .continuous).fill(isTargeted ? p.cardHover : p.card))
        .overlay(RoundedRectangle(cornerRadius: Radius.tile, style: .continuous)
            .strokeBorder(focused ? theme.accentColor : p.stroke, style: StrokeStyle(lineWidth: focused ? StrokeWidth.focus : StrokeWidth.emphasis,
                                                                                    dash: focused ? [] : StrokeWidth.dash)))
        .overlay(alignment: .trailing) { handle }
        .overlay(alignment: .top) {
            if let dragCells {
                Text(verbatim: LayoutRows.cells(dragCells)).crannyFont(.caption).foregroundStyle(.black)
                    .padding(.horizontal, Space.s).padding(.vertical, Space.xxs)
                    .background(Capsule().fill(.white)).offset(y: -Space.xl)
            }
        }
        .animation(theme.animation(.listReorder), value: shown)
        .contentShape(RoundedRectangle(cornerRadius: Radius.tile, style: .continuous))
        .draggable(info.id.rawValue)
        .dropDestination(for: String.self) { dropped, location in
            guard let raw = dropped.first, raw != info.id.rawValue else { return false }
            let after = location.x > metrics.width(cells: shown) / 2
            apply { editor in
                guard let items = editor.page(pageID)?.items,
                      let target = items.firstIndex(where: { $0.widget == info.id }) else { return nil }
                let source = items.firstIndex { $0.widget.rawValue == raw } ?? 0
                let index = target + (after ? 1 : 0) - (source < target ? 1 : 0)
                editor.move(WidgetID(raw), on: pageID, to: index)
                return nil
            }
            haptics.play(.alignment)
            return true
        } isTargeted: { isTargeted = $0 }
        .contextMenu { menu }
        .focusable(interactions: .activate)       // in the key loop with keyboard navigation only, no ring by default
        .focused($focused)
        .focusEffectDisabled()
        .onKeyPress(keys: [.leftArrow, .rightArrow]) { press in
            guard press.modifiers.contains(.option) else { return .ignored }
            let step = press.key == .leftArrow ? -1 : 1
            if press.modifiers.contains(.shift) { resize(by: step) } else { shift(by: step) }
            return .handled
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: info.title))
        .accessibilityValue(Text(verbatim: LayoutRows.cells(cells)))
        .accessibilityAdjustableAction { direction in
            resize(by: direction == .increment ? 1 : -1)
        }
        .accessibilityAction(named: Text("Move Left", bundle: .module, comment: "Settings ▸ Layout & Widgets: move a widget or a page one place left")) { shift(by: -1) }
        .accessibilityAction(named: Text("Move Right", bundle: .module, comment: "Settings ▸ Layout & Widgets: move a widget or a page one place right")) { shift(by: 1) }
        .accessibilityAction(named: Text("Remove", bundle: .module, comment: "Settings ▸ Layout & Widgets: remove a widget from the page")) { remove() }
    }

    /// The 8 × 24 resize handle on the trailing edge.
    private var handle: some View {
        Capsule(style: .continuous)
            .fill(theme.palette.secondaryLabel)
            .frame(width: 4, height: 24)
            .frame(width: 8 + Space.s, height: metrics.cardHeight)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 2)
                .onChanged { value in
                    let step = metrics.cell + metrics.gutter
                    let delta = Int((value.translation.width / max(step, 1)).rounded())
                    let next = info.sizes.clamp(cells + delta)
                    if next != dragCells { haptics.play(.alignment) }
                    dragCells = next
                }
                .onEnded { _ in
                    if let target = dragCells { apply { $0.resize(info.id, on: pageID, to: target) } }
                    dragCells = nil
                })
            .modifier(ResizeCursor())
            .accessibilityHidden(true)
    }

    @ViewBuilder private var menu: some View {
        if info.hasOptions {
            Button { showOptions(info.id) } label: { Text("Options…", bundle: .module, comment: "Settings ▸ Layout & Widgets: opens a widget's options") }
        }
        Button { resize(by: 1) } label: { Text("Wider", bundle: .module, comment: "Settings ▸ Layout & Widgets: make a widget one cell wider") }
            .disabled(cells >= info.sizes.maximum)
        Button { resize(by: -1) } label: { Text("Narrower", bundle: .module, comment: "Settings ▸ Layout & Widgets: make a widget one cell narrower") }
            .disabled(cells <= info.sizes.minimum)
        Divider()
        Button { shift(by: -1) } label: { Text("Move Left", bundle: .module, comment: "Settings ▸ Layout & Widgets: move a widget or a page one place left") }
        Button { shift(by: 1) } label: { Text("Move Right", bundle: .module, comment: "Settings ▸ Layout & Widgets: move a widget or a page one place right") }
        Divider()
        Button(role: .destructive) { remove() } label: { Text("Remove", bundle: .module, comment: "Settings ▸ Layout & Widgets: remove a widget from the page") }
    }

    private func shift(by offset: Int) {
        apply { $0.shift(info.id, on: pageID, by: offset); return nil }
    }

    /// One cell wider (+1) or narrower (−1). The new width is announced only when it was applied; a refusal is
    /// announced by the pane ("1 cell over…").
    private func resize(by delta: Int) {
        let target = info.sizes.clamp(cells + delta)
        guard apply({ $0.resize(info.id, on: pageID, to: target) }) else { return }
        AccessibilityNotification.Announcement(LayoutRows.width(of: info.title, cells: target)).post()
    }

    private func remove() {
        apply { $0.remove(info.id, from: pageID); return nil }
    }
}

/// The left-right resize pointer over the handle (`pointerStyle` on macOS 15+, the cursor stack before).
private struct ResizeCursor: ViewModifier {
    @State private var pushed = false

    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content.pointerStyle(.frameResize(position: .trailing, directions: [.inward, .outward]))
        } else {
            content
                .onHover { inside in
                    if inside, !pushed { NSCursor.resizeLeftRight.push(); pushed = true }
                    if !inside, pushed { NSCursor.pop(); pushed = false }
                }
                .onDisappear { if pushed { NSCursor.pop(); pushed = false } }
        }
    }
}

/// "+" at the end of the row: the free cells, and the door to the library.
private struct AddTile: View {
    @Environment(\.cranny) private var theme
    let cellsLeft: Int
    let width: CGFloat
    let height: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: Space.xs) {
                Image(systemName: "plus").font(.system(size: 15, weight: .semibold))
                if cellsLeft > 0 {
                    Text(verbatim: String(localized: "\(cellsLeft) cells left", bundle: .module,
                                          comment: "Settings ▸ Layout & Widgets: free cells on the page (plural)"))
                        .crannyFont(.caption).lineLimit(1).minimumScaleFactor(0.7)
                }
            }
            .foregroundStyle(theme.palette.secondaryLabel)
            .frame(width: width, height: height)
            .background(RoundedRectangle(cornerRadius: Radius.tile, style: .continuous)
                .strokeBorder(theme.palette.stroke, style: StrokeStyle(lineWidth: StrokeWidth.emphasis, dash: StrokeWidth.dash)))
            .contentShape(RoundedRectangle(cornerRadius: Radius.tile, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Add Widget", bundle: .module, comment: "Settings ▸ Layout & Widgets: opens the widget library"))
    }
}

#Preview("Grid editor") {
    let registry = ModuleRegistry(services: .preview())
    let page = NookPreset.listener.page
    GridEditor(page: page, editor: LayoutEditor(pages: [page], maxColumns: 12, sizes: [:]), registry: registry,
               theme: CrannyTheme(), apply: .preview, showOptions: { _ in })
        .padding()
        .frame(width: 620)
}
