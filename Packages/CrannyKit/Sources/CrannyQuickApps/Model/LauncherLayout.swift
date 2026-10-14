// CrannyQuickApps/Model/LauncherLayout.swift — which tile goes where in the launcher card (pure, tested).
//
// DESIGN.md §7.3 / §6.7: the launcher is N cells wide and each cell column holds 2 tiles, so a tile IS a grid
// cell (56 pt at Standard density) and tiles sit on the Nook's grid, not inside the card padding. Tiles fill
// columns top to bottom (column-major): growing the widget by a column appends tiles, it never reshuffles them.
import CoreGraphics
import Foundation

/// Tile size and spacing of one launcher card (from the Nook grid, see `init(cardSize:columns:rows:cell:)`).
nonisolated struct LauncherMetrics: Equatable, Sendable {
    var tile: CGFloat
    var horizontalSpacing: CGFloat
    var verticalSpacing: CGFloat

    init(tile: CGFloat, horizontalSpacing: CGFloat, verticalSpacing: CGFloat) {
        self.tile = tile; self.horizontalSpacing = horizontalSpacing; self.verticalSpacing = verticalSpacing
    }

    /// Spacing that puts `columns × rows` tiles of `cell` exactly on a card of `cardSize` (the grid's gutter in
    /// both widget styles, because the card is `n·cell + (n−1)·gutter` wide).
    init(cardSize: CGSize, columns: Int, rows: Int, cell: CGFloat) {
        let c = max(columns, 1), r = max(rows, 1)
        tile = min(cell, cardSize.width / CGFloat(c), cardSize.height / CGFloat(r))
        horizontalSpacing = c > 1 ? max((cardSize.width - CGFloat(c) * tile) / CGFloat(c - 1), 0) : 0
        verticalSpacing = r > 1 ? max((cardSize.height - CGFloat(r) * tile) / CGFloat(r - 1), 0) : 0
    }
}

nonisolated struct LauncherLayout: Equatable, Sendable {
    /// What one grid position shows.
    enum Slot: Hashable, Sendable {
        /// The visible tile at this index.
        case tile(Int)
        /// "+N": the tiles from `first` on, listed in a menu.
        case overflow(first: Int, count: Int)
        /// Add an app or a shortcut (edit mode, or the only slot of an empty launcher).
        case add
    }

    let columns: Int
    let rows: Int
    var capacity: Int { columns * rows }

    init(columns: Int, rows: Int) {
        self.columns = max(columns, 1); self.rows = max(rows, 1)
    }

    /// The slots in display order. When the tiles do not fit, the last free position becomes "+N" (before the
    /// add slot, which always stays last).
    func slots(tileCount: Int, showsAddTile: Bool) -> [Slot] {
        let count = max(tileCount, 0)
        let reserved = showsAddTile ? 1 : 0
        var result: [Slot]
        if count + reserved <= capacity {
            result = (0..<count).map(Slot.tile)
        } else {
            let shown = max(capacity - reserved - 1, 0)
            result = (0..<shown).map(Slot.tile) + [.overflow(first: shown, count: count - shown)]
        }
        if showsAddTile { result.append(.add) }
        return result
    }

    /// Column and row of a slot (column-major).
    func cell(of slot: Int) -> (column: Int, row: Int) {
        (slot / rows, slot % rows)
    }

    /// Top-left corner of a slot, relative to the card's top-left corner.
    func origin(of slot: Int, metrics m: LauncherMetrics) -> CGPoint {
        let (column, row) = cell(of: slot)
        return CGPoint(x: CGFloat(column) * (m.tile + m.horizontalSpacing), y: CGFloat(row) * (m.tile + m.verticalSpacing))
    }

    /// The slot nearest to `point` (card coordinates), clamped to `0..<limit`: the drop target while reordering.
    func slot(at point: CGPoint, metrics m: LauncherMetrics, limit: Int) -> Int {
        guard limit > 0 else { return 0 }
        let column = Int(((point.x + m.horizontalSpacing / 2) / (m.tile + m.horizontalSpacing)).rounded(.down))
        let row = Int(((point.y + m.verticalSpacing / 2) / (m.tile + m.verticalSpacing)).rounded(.down))
        let slot = min(max(column, 0), columns - 1) * rows + min(max(row, 0), rows - 1)
        return min(slot, limit - 1)
    }

    /// The slot a keyboard arrow moves to, or nil at the edge (↑ ↓ within a column, ← → across columns).
    func neighbour(of slot: Int, _ direction: MoveDirection, count: Int) -> Int? {
        let (column, row) = cell(of: slot)
        let next: Int? = switch direction {
        case .up: row > 0 ? slot - 1 : nil
        case .down: row < rows - 1 ? slot + 1 : nil
        case .left: column > 0 ? slot - rows : nil
        case .right: column < columns - 1 ? slot + rows : nil
        }
        guard let next, next >= 0, next < count else { return nil }
        return next
    }

    enum MoveDirection: Sendable { case up, down, left, right }
}
