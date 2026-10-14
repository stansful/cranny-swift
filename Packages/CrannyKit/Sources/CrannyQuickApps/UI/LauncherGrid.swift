// CrannyQuickApps/UI/LauncherGrid.swift — tiles placed on the card's cells (column-major), the "+N" and "+"
// tiles, keyboard focus and arrows, and drag-to-reorder in edit mode. Positions animate with `listReorder`.
import CrannyCore
import SwiftUI

struct LauncherGrid: View {
    static let space = "quickapps.grid"

    @Environment(\.cranny) private var theme
    let model: QuickAppsModel
    let tiles: [LauncherTile]
    let layout: LauncherLayout
    let metrics: LauncherMetrics
    let interactive: Bool
    let redacted: Bool

    @State private var drag: Drag?
    @FocusState private var focus: TileID?

    /// A tile being dragged in edit mode: where it started and where it would land.
    private struct Drag: Equatable {
        var id: TileID
        var from: Int
        var translation: CGSize
        var target: Int
    }

    var body: some View {
        let editing = model.isEditing && interactive
        let showsAdd = interactive && (editing || tiles.isEmpty)
        let slots = layout.slots(tileCount: tiles.count, showsAddTile: showsAdd)
        let shown = previewOrder
        let tileMetrics = TileMetrics(tile: metrics.tile, showsLabels: model.showsLabels)
        ZStack(alignment: .topLeading) {
            ForEach(items(slots: slots, shown: shown)) { item in
                switch item {
                case .tile(let tile, let index, let position):
                    let isDragged = drag?.id == tile.id
                    LauncherTileView(tile: tile, index: index, count: tiles.count, model: model, metrics: tileMetrics,
                                     interactive: interactive, redacted: redacted, isFocused: focus == tile.id,
                                     onDrag: { dragChanged(tile, from: index, $0) }, onDragEnd: dragEnded)
                        .focusable(interactive, interactions: .activate)
                        .focused($focus, equals: tile.id)
                        .focusEffectDisabled()
                        .scaleEffect(isDragged && !theme.reduceMotion ? 1.06 : 1)
                        .crannyElevation(Elevation.lifted, amount: isDragged ? 1 : 0)
                        .zIndex(isDragged ? 1 : 0)
                        .offset(offset(for: tile, at: position))
                        .transaction { if isDragged { $0.animation = nil } }
                        .transition(.quickAppsTile(reduceMotion: theme.reduceMotion))
                case .overflow(let first, let count, let position):
                    OverflowTile(tiles: Array(shown[first...]), count: count, model: model, metrics: tileMetrics,
                                 interactive: interactive, redacted: redacted)
                        .offset(at(position))
                case .add(let position):
                    AddTile(model: model, metrics: tileMetrics)
                        .offset(at(position))
                        .transition(.quickAppsTile(reduceMotion: theme.reduceMotion))
                }
            }
        }
        .frame(width: cardWidth, height: cardHeight, alignment: .topLeading)
        .coordinateSpace(.named(Self.space))
        .animation(theme.animation(.listReorder), value: shown.map(\.id))
        .animation(theme.animation(.listReorder), value: slots)
        .onKeyPress(phases: .down) { press in handleKey(press) }
        .onChange(of: drag?.target) { old, new in
            if old != nil, new != nil, old != new { model.haptics.play(.alignment) }
        }
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

    /// Tiles that can be reordered by dragging (not the "+N" and "+" positions).
    private var reorderLimit: Int {
        let slots = layout.slots(tileCount: tiles.count, showsAddTile: true)
        return slots.reduce(0) { count, slot in if case .tile = slot { count + 1 } else { count } }
    }

    private func dragChanged(_ tile: LauncherTile, from index: Int, _ value: DragGesture.Value) {
        let from = drag?.from ?? tiles.firstIndex(of: tile) ?? index
        let start = layout.origin(of: from, metrics: metrics)
        let centre = CGPoint(x: start.x + metrics.tile / 2 + value.translation.width,
                             y: start.y + metrics.tile / 2 + value.translation.height)
        let target = layout.slot(at: CGPoint(x: centre.x - metrics.tile / 2, y: centre.y - metrics.tile / 2),
                                 metrics: metrics, limit: reorderLimit)
        drag = Drag(id: tile.id, from: from, translation: value.translation, target: target)
    }

    private func dragEnded() {
        guard let drag else { return }
        withAnimation(theme.animation(.listReorder)) {
            model.move(drag.id, toVisibleIndex: drag.target)
            self.drag = nil
        }
    }

    // MARK: Keyboard (arrows within, ↩ / Space open, ⌥ arrows move in edit mode)

    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        guard interactive, let focus, let index = tiles.firstIndex(where: { $0.id == focus }) else { return .ignored }
        let direction: LauncherLayout.MoveDirection? = switch press.key {
        case .upArrow: .up
        case .downArrow: .down
        case .leftArrow: .left
        case .rightArrow: .right
        default: nil
        }
        if let direction, let next = layout.neighbour(of: index, direction, count: min(tiles.count, reorderLimit)) {
            if press.modifiers.contains(.option) && model.isEditing {
                withAnimation(theme.animation(.listReorder)) { model.move(focus, toVisibleIndex: next) }
            } else {
                self.focus = tiles[next].id
            }
            return .handled
        }
        if press.key == .return || press.key == .space {
            if !model.isEditing { model.activate(tiles[index]) }
            return .handled
        }
        if press.key == .delete && model.isEditing {
            model.remove(focus)
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
