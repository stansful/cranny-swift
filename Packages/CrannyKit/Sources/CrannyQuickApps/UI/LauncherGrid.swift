// CrannyQuickApps/UI/LauncherGrid.swift — tiles placed on the card's cells (column-major), the "+N" and "+"
// tiles, keyboard focus and arrows, and drag-to-reorder in edit mode. Positions animate with `listReorder`.
//
// Keyboard (DESIGN.md §7.3, §16): the arrows walk every stop the card shows — tiles, "+N", "+" (`LauncherFocus`);
// ↩ / Space open a tile or pop up the "+N" / "+" menu under its tile; in edit mode ⌥ + arrow moves a tile and ⌫
// removes it, keeping the focus on the tile that takes its place. Right to left the columns run from the right
// (the offsets are mirrored with the layout): ← → and a drag's travel are turned into steps along the row.
import CrannyCore
import SwiftUI

struct LauncherGrid: View {
    static let space = "quickapps.grid"

    @Environment(\.cranny) private var theme
    @Environment(\.layoutDirection) private var direction
    let model: QuickAppsModel
    let tiles: [LauncherTile]
    let layout: LauncherLayout
    let metrics: LauncherMetrics
    let interactive: Bool
    let redacted: Bool
    /// On screen in the Nook (not a widget-library preview): the grid tells the model which tiles it shows, so a
    /// shortcut in "+N" or on a hidden page reports its result in the notch instead (`QuickAppsModel.present`).
    var reportsVisibleTiles = false

    @State private var drag: Drag?
    @State private var launcherID = UUID()
    @State private var addMenu = MenuAnchor()
    @State private var overflowMenu = MenuAnchor()
    @FocusState private var focus: LauncherFocus?

    /// A tile being dragged in edit mode: where it started and where it would land.
    private struct Drag: Equatable {
        var id: TileID
        var from: Int
        var translation: CGSize          // along the layout (x: leading → trailing), not the pointer's physical travel
        var target: Int
    }

    var body: some View {
        let slots = self.slots
        let shown = previewOrder
        let tileMetrics = TileMetrics(tile: metrics.tile, showsLabels: model.showsLabels)
        let visible = LauncherLayout.tilesShown(slots, tileIDs: tiles.map(\.id))
        ZStack(alignment: .topLeading) {
            ForEach(items(slots: slots, shown: shown)) { item in
                switch item {
                case .tile(let tile, let index, let position):
                    let isDragged = drag?.id == tile.id
                    LauncherTileView(tile: tile, index: index, count: tiles.count, model: model, metrics: tileMetrics,
                                     interactive: interactive, redacted: redacted, isFocused: focus == .tile(tile.id),
                                     onDrag: { dragChanged(tile, from: index, $0) }, onDragEnd: dragEnded)
                        .focusable(interactive, interactions: .activate)
                        .focused($focus, equals: .tile(tile.id))
                        .focusEffectDisabled()
                        .scaleEffect(isDragged && !theme.reduceMotion ? 1.06 : 1)
                        .crannyElevation(Elevation.lifted, amount: isDragged ? 1 : 0)
                        .zIndex(isDragged ? 1 : 0)
                        .offset(offset(for: tile, at: position))
                        .transaction { if isDragged { $0.animation = nil } }
                        .transition(.quickAppsTile(reduceMotion: theme.reduceMotion))
                case .overflow(let first, let count, let position):
                    OverflowTile(tiles: Array(shown[first...]), count: count, model: model, metrics: tileMetrics,
                                 interactive: interactive, redacted: redacted, anchor: overflowMenu)
                        .focusable(interactive, interactions: .activate)
                        .focused($focus, equals: .overflow)
                        .focusEffectDisabled()
                        .crannyFocusRing(focus == .overflow, radius: Radius.tile)
                        .offset(at(position))
                case .add(let position):
                    AddTile(model: model, metrics: tileMetrics, anchor: addMenu)
                        .focusable(interactive, interactions: .activate)
                        .focused($focus, equals: .add)
                        .focusEffectDisabled()
                        .crannyFocusRing(focus == .add, radius: Radius.tile)
                        .offset(at(position))
                        .transition(.quickAppsTile(reduceMotion: theme.reduceMotion))
                }
            }
        }
        .frame(width: cardWidth, height: cardHeight, alignment: .topLeading)
        .coordinateSpace(.named(Self.space))
        .animation(theme.animation(.listReorder), value: shown.map(\.id))
        .animation(theme.animation(.listReorder), value: slots)
        .onKeyPress(phases: .down) { press in handleKey(press, slots: slots, shown: shown) }
        .onChange(of: drag?.target) { old, new in
            if old != nil, new != nil, old != new { model.haptics.play(.alignment) }
        }
        .onChange(of: focus) { _, new in if new == .add { model.prepareShortcutList() } }
        .onChange(of: visible, initial: true) { _, visible in
            if reportsVisibleTiles { model.present(visible, by: launcherID) }
        }
        .onDisappear { model.withdrawTiles(of: launcherID) }
    }

    /// What each position shows: tiles, then "+N" when they do not fit, then "+" in edit mode (or when empty).
    private var slots: [LauncherLayout.Slot] {
        let showsAdd = interactive && (model.isEditing || tiles.isEmpty)
        return layout.slots(tileCount: tiles.count, showsAddTile: showsAdd)
    }

    /// One positioned element; identity follows the tile, so a reorder MOVES views instead of replacing them.
    private enum Item: Identifiable {
        case tile(LauncherTile, index: Int, position: Int)
        case overflow(first: Int, count: Int, position: Int)
        case add(position: Int)

        var id: String {
            switch self {
            case .tile(let tile, _, _): tile.id.rawValue
            case .overflow: "overflow"
            case .add: "add"
            }
        }
    }

    private func items(slots: [LauncherLayout.Slot], shown: [LauncherTile]) -> [Item] {
        slots.enumerated().map { position, slot in
            switch slot {
            case .tile(let index): .tile(shown[index], index: index, position: position)
            case .overflow(let first, let count): .overflow(first: first, count: count, position: position)
            case .add: .add(position: position)
            }
        }
    }

    // MARK: Geometry

    private var cardWidth: CGFloat {
        CGFloat(layout.columns) * metrics.tile + CGFloat(layout.columns - 1) * metrics.horizontalSpacing
    }
    private var cardHeight: CGFloat {
        CGFloat(layout.rows) * metrics.tile + CGFloat(layout.rows - 1) * metrics.verticalSpacing
    }

    private func at(_ slot: Int) -> CGSize {
        let origin = layout.origin(of: slot, metrics: metrics)
        return CGSize(width: origin.x, height: origin.y)
    }

    /// The dragged tile follows the pointer from its own slot; every other tile sits in its (preview) slot.
    private func offset(for tile: LauncherTile, at slot: Int) -> CGSize {
        guard let drag, drag.id == tile.id else { return at(slot) }
        let start = at(drag.from)
        return CGSize(width: start.width + drag.translation.width, height: start.height + drag.translation.height)
    }

    // MARK: Reorder

    /// The tiles with the dragged one moved to its target (what the user will get on release).
    private var previewOrder: [LauncherTile] {
        guard let drag, let from = tiles.firstIndex(where: { $0.id == drag.id }) else { return tiles }
        var order = tiles
        let moved = order.remove(at: from)
        order.insert(moved, at: min(drag.target, order.count))
        return order
    }

    /// Tile positions a drag can land on in edit mode (not the "+N" and "+" positions).
    private var reorderLimit: Int {
        LauncherLayout.tileSlotCount(layout.slots(tileCount: tiles.count, showsAddTile: true))
    }

    private func dragChanged(_ tile: LauncherTile, from index: Int, _ value: DragGesture.Value) {
        let from = drag?.from ?? tiles.firstIndex(of: tile) ?? index
        let translation = direction.alongLayout(value.translation)
        let target = layout.dropTarget(from: from, translation: translation, metrics: metrics, limit: reorderLimit)
        drag = Drag(id: tile.id, from: from, translation: translation, target: target)
    }

    private func dragEnded() {
        guard let drag else { return }
        withAnimation(theme.animation(.listReorder)) {
            model.move(drag.id, toVisibleIndex: drag.target)
            self.drag = nil
        }
    }

    // MARK: Keyboard

    private func handleKey(_ press: KeyPress, slots: [LauncherLayout.Slot], shown: [LauncherTile]) -> KeyPress.Result {
        guard interactive, let focus else { return .ignored }
        let editing = model.isEditing
        let direction = LauncherLayout.MoveDirection(press.key, layoutDirection: self.direction)
        if let direction {
            if editing, press.modifiers.contains(.option) {
                guard case .tile(let id) = focus, let index = tiles.firstIndex(where: { $0.id == id }),
                      let target = layout.moveTarget(of: index, direction, slots: slots) else { return .ignored }
                withAnimation(theme.animation(.listReorder)) { model.move(id, toVisibleIndex: target) }
                return .handled
            }
            let stops = LauncherLayout.focusStops(slots, tileIDs: shown.map(\.id))
            guard let next = layout.focus(from: focus, direction, stops: stops) else { return .ignored }
            self.focus = next
            return .handled
        }
        if press.key == .return || press.key == .space {
            switch focus {
            case .tile(let id):
                if !editing, let tile = tiles.first(where: { $0.id == id }) { model.activate(tile) }
            case .overflow:
                guard let first = slots.lazy.compactMap({ slot -> Int? in
                    if case .overflow(let first, _) = slot { first } else { nil }
                }).first else { break }
                OverflowTile.showMenu(tiles: Array(shown[first...]), model: model, redacted: redacted, anchor: overflowMenu)
            case .add:
                AddTile.showMenu(model: model, anchor: addMenu)
            }
            return .handled
        }
        if press.key == .delete, editing, case .tile(let id) = focus, let index = tiles.firstIndex(where: { $0.id == id }) {
            self.focus = LauncherLayout.focusAfterRemoving(at: index, from: tiles.map(\.id))
            withAnimation(theme.animation(.listReorder)) { model.remove(id) }
            return .handled
        }
        return .ignored
    }
}

extension AnyTransition {
    /// A tile arriving or leaving: grows from 0.6 with a fade (opacity only under Reduce Motion).
    static func quickAppsTile(reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .opacity : .scale(scale: 0.6).combined(with: .opacity)
    }
}

extension LauncherLayout.MoveDirection {
    /// The move an arrow key asks for. Right to left the columns run from the right, so ← walks to the next column
    /// and → to the previous one: the focus and a moved tile go the way the arrow points. Nil for any other key.
    init?(_ key: KeyEquivalent, layoutDirection: LayoutDirection) {
        switch key {
        case .upArrow: self = .up
        case .downArrow: self = .down
        default:
            guard let step = layoutDirection.step(for: key) else { return nil }
            self = step < 0 ? .left : .right
        }
    }
}

#Preview("Grid · 3 columns, editing") {
    let model = QuickAppsPreview.model(editing: true)
    let layout = LauncherLayout(columns: 3, rows: 2)
    LauncherGrid(model: model, tiles: model.tiles, layout: layout,
                 metrics: LauncherMetrics(tile: 56, horizontalSpacing: 8, verticalSpacing: 8),
                 interactive: true, redacted: false)
        .padding(-12)
        .crannyCard(cells: 3)
        .padding(Space.xl)
        .background(.black)
        .crannyThemeRoot(CrannyTheme())
}
