// Keyboard stops and drag targets: the arrows reach everything the card shows ("+N" and "+" included), ⌥ + arrow
// and drags stay on tile positions, the drag target follows the tile's centre, Delete keeps the focus in place.
import CoreGraphics
import SwiftUI
import Testing
@testable import CrannyQuickApps

private let ids: [TileID] = (0..<9).map { TileID.app("app\($0)") }

private func stops(_ layout: LauncherLayout, tiles: Int, editing: Bool) -> [LauncherFocus] {
    LauncherLayout.focusStops(layout.slots(tileCount: tiles, showsAddTile: editing), tileIDs: Array(ids.prefix(tiles)))
}

@Test func arrowsReachEveryTileOfTheDefaultLauncher() {
    // Regression: 2 cells holding Finder, Safari, Mail and Music (not editing) — Mail and Music were unreachable.
    let layout = LauncherLayout(columns: 2, rows: 2)
    let all = stops(layout, tiles: 4, editing: false)
    #expect(all == ids.prefix(4).map(LauncherFocus.tile))
    #expect(layout.focus(from: .tile(ids[0]), .right, stops: all) == .tile(ids[2]))
    #expect(layout.focus(from: .tile(ids[1]), .right, stops: all) == .tile(ids[3]))
    #expect(layout.focus(from: .tile(ids[2]), .down, stops: all) == .tile(ids[3]))
    #expect(layout.focus(from: .tile(ids[3]), .up, stops: all) == .tile(ids[2]))
    #expect(layout.focus(from: .tile(ids[3]), .left, stops: all) == .tile(ids[1]))
    #expect(layout.focus(from: .tile(ids[2]), .right, stops: all) == nil)          // the card's edge
}

@Test func overflowAndAddAreKeyboardStops() {
    let layout = LauncherLayout(columns: 2, rows: 2)
    let overflowing = stops(layout, tiles: 5, editing: false)                     // t0 t1 t2 +2
    #expect(overflowing == [.tile(ids[0]), .tile(ids[1]), .tile(ids[2]), .overflow])
    #expect(layout.focus(from: .tile(ids[1]), .right, stops: overflowing) == .overflow)
    #expect(layout.focus(from: .tile(ids[2]), .down, stops: overflowing) == .overflow)
    #expect(layout.focus(from: .overflow, .left, stops: overflowing) == .tile(ids[1]))

    let editing = stops(layout, tiles: 4, editing: true)                          // t0 t1 +2 +
    #expect(editing == [.tile(ids[0]), .tile(ids[1]), .overflow, .add])
    #expect(layout.focus(from: .tile(ids[0]), .right, stops: editing) == .overflow)
    #expect(layout.focus(from: .overflow, .down, stops: editing) == .add)
    #expect(layout.focus(from: .add, .left, stops: editing) == .tile(ids[1]))

    let empty = stops(LauncherLayout(columns: 1, rows: 2), tiles: 0, editing: true)
    #expect(empty == [.add])
    #expect(layout.focus(from: .tile(ids[8]), .down, stops: editing) == nil)      // not on the card
}

@Test func optionArrowsMoveTilesAmongTilePositionsOnly() {
    let layout = LauncherLayout(columns: 2, rows: 2)
    let slots = layout.slots(tileCount: 4, showsAddTile: true)                    // t0 t1 +2 +
    #expect(LauncherLayout.tileSlotCount(slots) == 2)
    #expect(layout.moveTarget(of: 0, .down, slots: slots) == 1)
    #expect(layout.moveTarget(of: 0, .right, slots: slots) == nil)                // "+N" is not a tile position
    let roomy = LauncherLayout(columns: 3, rows: 2).slots(tileCount: 4, showsAddTile: true)   // t0…t3 +
    #expect(LauncherLayout(columns: 3, rows: 2).moveTarget(of: 1, .right, slots: roomy) == 3)
}

@Test func dragTargetFollowsTheTilesCentreInEveryDirection() {
    // Regression: the tile's corner was hit-tested, so 5 pt up or left retargeted and 59 pt right did not.
    let layout = LauncherLayout(columns: 3, rows: 2)
    let m = LauncherMetrics(tile: 56, horizontalSpacing: 8, verticalSpacing: 8)  // 64 pt from cell to cell
    func target(_ slot: Int, _ dx: CGFloat, _ dy: CGFloat) -> Int {
        layout.dropTarget(from: slot, translation: CGSize(width: dx, height: dy), metrics: m, limit: 6)
    }
    #expect(target(3, 0, -5) == 3)
    #expect(target(3, -5, 0) == 3)
    #expect(target(3, 0, -31) == 3)
    #expect(target(3, 0, -33) == 2)           // half-way up
    #expect(target(3, -31, 0) == 3)
    #expect(target(3, -33, 0) == 1)           // half-way left
    #expect(target(0, 31, 0) == 0)
    #expect(target(0, 33, 0) == 2)            // half-way right
    #expect(target(0, 59, 0) == 2)
    #expect(target(0, 0, 31) == 0)
    #expect(target(0, 0, 33) == 1)            // half-way down
    #expect(target(0, 500, 500) == 5)
    #expect(layout.dropTarget(from: 0, translation: CGSize(width: 500, height: 500), metrics: m, limit: 4) == 3)
}

@Test func deleteMovesTheFocusToTheTileTakingItsPlace() {
    let three = Array(ids.prefix(3))
    #expect(LauncherLayout.focusAfterRemoving(at: 0, from: three) == .tile(ids[1]))
    #expect(LauncherLayout.focusAfterRemoving(at: 1, from: three) == .tile(ids[2]))
    #expect(LauncherLayout.focusAfterRemoving(at: 2, from: three) == .tile(ids[1]))   // the last: the previous one
    #expect(LauncherLayout.focusAfterRemoving(at: 0, from: [ids[0]]) == .add)         // the only one: "+"
}

@Test func tilesInOverflowAreNotShownAsTiles() {
    let layout = LauncherLayout(columns: 2, rows: 2)
    let shown = LauncherLayout.tilesShown(layout.slots(tileCount: 5, showsAddTile: false), tileIDs: Array(ids.prefix(5)))
    #expect(shown == Set(ids.prefix(3)))
    let all = LauncherLayout.tilesShown(layout.slots(tileCount: 4, showsAddTile: false), tileIDs: Array(ids.prefix(4)))
    #expect(all == Set(ids.prefix(4)))
}

/// Right to left the columns run from the right (Arabic, Hebrew): ← walks to the next column, the one on its left, and
/// → back; ↑ ↓ are the same in every language.
@Test func arrowsGoTheWayTheyPointRightToLeft() {
    typealias Move = LauncherLayout.MoveDirection
    #expect(Move(.leftArrow, layoutDirection: .leftToRight) == .left && Move(.rightArrow, layoutDirection: .leftToRight) == .right)
    #expect(Move(.leftArrow, layoutDirection: .rightToLeft) == .right && Move(.rightArrow, layoutDirection: .rightToLeft) == .left)
    #expect(Move(.upArrow, layoutDirection: .rightToLeft) == .up && Move(.downArrow, layoutDirection: .rightToLeft) == .down)
    #expect(Move(.return, layoutDirection: .rightToLeft) == nil)
    let layout = LauncherLayout(columns: 2, rows: 2)
    let all = stops(layout, tiles: 4, editing: false)
    if let left = Move(.leftArrow, layoutDirection: .rightToLeft) {
        #expect(layout.focus(from: .tile(ids[0]), left, stops: all) == .tile(ids[2]))     // column 0 is the right one
    }
}
