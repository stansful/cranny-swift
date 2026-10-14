// CrannyQuickApps/Model/LauncherFocus.swift — keyboard stops and moves in the launcher (pure, tested).
//
// DESIGN.md §7.3 "arrows within", §16 "every action has a key path": the arrows walk every position the card
// SHOWS — the visible tiles, "+N" and "+" — never a position computed for another mode. ⌥ + arrow (edit mode)
// and drags move tiles among the tile positions only.
import CoreGraphics
import Foundation

/// A keyboard stop in the launcher.
nonisolated enum LauncherFocus: Hashable, Sendable {
    case tile(TileID)
    /// "+N": opens the menu of the tiles that do not fit.
    case overflow
    /// "+": the add menu (edit mode, or an empty launcher).
    case add
}

extension LauncherLayout {
    /// How many slots show a tile (not "+N" or "+").
    static func tileSlotCount(_ slots: [Slot]) -> Int {
        slots.reduce(0) { count, slot in if case .tile = slot { count + 1 } else { count } }
    }

    /// The keyboard stop of each slot, in slot order. `tileIDs` are the tiles in display order.
    static func focusStops(_ slots: [Slot], tileIDs: [TileID]) -> [LauncherFocus] {
        slots.compactMap { slot in
            switch slot {
            case .tile(let index): tileIDs.indices.contains(index) ? .tile(tileIDs[index]) : nil
            case .overflow: .overflow
            case .add: .add
            }
        }
    }

    /// Where an arrow moves keyboard focus from `focus`: the neighbouring stop on the card (↑ ↓ within a column,
    /// ← → across columns), or nil at an edge or when `focus` is not on the card.
    func focus(from focus: LauncherFocus, _ direction: MoveDirection, stops: [LauncherFocus]) -> LauncherFocus? {
        guard let position = stops.firstIndex(of: focus),
              let next = neighbour(of: position, direction, count: stops.count) else { return nil }
        return stops[next]
    }

    /// The tile index a tile moves to with ⌥ + arrow in edit mode: tile positions only, never "+N" or "+".
    func moveTarget(of index: Int, _ direction: MoveDirection, slots: [Slot]) -> Int? {
        neighbour(of: index, direction, count: Self.tileSlotCount(slots))
    }

    /// Where a tile dragged from `slot` by `translation` would land: the slot under the tile's CENTRE (clamped to
    /// `0..<limit`), so the target changes when the tile is half-way over the next cell, the same in every direction.
    func dropTarget(from slot: Int, translation: CGSize, metrics m: LauncherMetrics, limit: Int) -> Int {
        let start = origin(of: slot, metrics: m)
        let centre = CGPoint(x: start.x + m.tile / 2 + translation.width, y: start.y + m.tile / 2 + translation.height)
        return self.slot(at: centre, metrics: m, limit: limit)
    }

    /// Focus after Delete removed the tile at `index` (edit mode): the next tile, which moves into its place, else
    /// the previous one, else "+" (always shown in edit mode).
    static func focusAfterRemoving(at index: Int, from tileIDs: [TileID]) -> LauncherFocus {
        if tileIDs.indices.contains(index + 1) { return .tile(tileIDs[index + 1]) }
        if index > 0, tileIDs.indices.contains(index - 1) { return .tile(tileIDs[index - 1]) }
        return .add
    }

    /// The tiles a card shows as tiles (not in "+N"): they show their own run state, the others need the notch.
    static func tilesShown(_ slots: [Slot], tileIDs: [TileID]) -> Set<TileID> {
        Set(focusStops(slots, tileIDs: tileIDs).compactMap { stop in if case .tile(let id) = stop { id } else { nil } })
    }
}
