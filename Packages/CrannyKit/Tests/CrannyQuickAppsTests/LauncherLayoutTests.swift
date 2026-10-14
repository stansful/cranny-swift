// Where tiles go on the card: capacity, "+N" overflow, the add tile, column-major positions, reorder targets.
import CoreGraphics
import CrannyCore
import Testing
@testable import CrannyQuickApps

@Test func columnsOfTwoTiles() {
    #expect(LauncherLayout(columns: 1, rows: 2).capacity == 2)
    #expect(LauncherLayout(columns: 2, rows: 2).capacity == 4)
    #expect(LauncherLayout(columns: 6, rows: 2).capacity == 12)
    #expect(LauncherLayout(columns: 0, rows: 0).capacity == 1)        // clamped
}

@Test func tilesThatFitAreAllShown() {
    let layout = LauncherLayout(columns: 2, rows: 2)
    #expect(layout.slots(tileCount: 4, showsAddTile: false) == [.tile(0), .tile(1), .tile(2), .tile(3)])
    #expect(layout.slots(tileCount: 3, showsAddTile: true) == [.tile(0), .tile(1), .tile(2), .add])
    #expect(layout.slots(tileCount: 0, showsAddTile: true) == [.add])
    #expect(layout.slots(tileCount: 0, showsAddTile: false).isEmpty)
}

@Test func overflowTakesTheLastFreeCell() {
    let layout = LauncherLayout(columns: 2, rows: 2)
    #expect(layout.slots(tileCount: 7, showsAddTile: false) == [.tile(0), .tile(1), .tile(2), .overflow(first: 3, count: 4)])
    #expect(layout.slots(tileCount: 4, showsAddTile: true) == [.tile(0), .tile(1), .overflow(first: 2, count: 2), .add])
    // One column while editing: "+N" and "+" only.
    #expect(LauncherLayout(columns: 1, rows: 2).slots(tileCount: 3, showsAddTile: true) == [.overflow(first: 0, count: 3), .add])
}

@Test func slotsAreColumnMajorOnTheGrid() {
    let layout = LauncherLayout(columns: 3, rows: 2)
    let metrics = LauncherMetrics(tile: 56, horizontalSpacing: 8, verticalSpacing: 8)
    #expect(layout.cell(of: 0) == (0, 0))
    #expect(layout.cell(of: 1) == (0, 1))
    #expect(layout.cell(of: 2) == (1, 0))
    #expect(layout.origin(of: 3, metrics: metrics) == CGPoint(x: 64, y: 64))
    #expect(layout.origin(of: 4, metrics: metrics) == CGPoint(x: 128, y: 0))
}

@Test func metricsPutTilesExactlyOnTheCard() {
    for density in NookDensity.allCases {
        for style in WidgetStyle.allCases {
            let grid = NookGrid(density: density, style: style)
            for cells in 1...6 {
                let card = CGSize(width: grid.width(cells: cells), height: grid.height)
                let m = LauncherMetrics(cardSize: card, columns: cells, rows: 2, cell: grid.cell)
                #expect(m.tile == grid.cell)
                #expect(abs(CGFloat(cells) * m.tile + CGFloat(cells - 1) * m.horizontalSpacing - card.width) < 0.001)
                #expect(abs(2 * m.tile + m.verticalSpacing - card.height) < 0.001)
            }
        }
    }
}

@Test func standardTileIsTheDesignedSize() {
    let tile = TileMetrics(tile: NookGrid().cell, showsLabels: false)
    #expect(tile.tile == 56)
    #expect(tile.icon == 36)                         // DESIGN.md §7.3: 36-pt icon in a 56-pt cell
    #expect(tile.body == 29)                         // squircles on the macOS icon grid (824/1024 of the canvas)
    #expect(tile.inset == 3.5)
    #expect(abs(tile.squircleRadius - 6.525) < 0.001)
    #expect(tile.glyph == 16)
    #expect(TileMetrics(tile: 56, showsLabels: true).icon == 30)
    #expect(TileMetrics(tile: 68, showsLabels: false).icon == 44)    // XL text grows the cell, the icon follows
}

@Test func dropTargetIsTheNearestSlot() {
    let layout = LauncherLayout(columns: 3, rows: 2)
    let m = LauncherMetrics(tile: 56, horizontalSpacing: 8, verticalSpacing: 8)
    #expect(layout.slot(at: CGPoint(x: 0, y: 0), metrics: m, limit: 6) == 0)
    #expect(layout.slot(at: CGPoint(x: 70, y: 60), metrics: m, limit: 6) == 3)
    #expect(layout.slot(at: CGPoint(x: 500, y: 500), metrics: m, limit: 6) == 5)
    #expect(layout.slot(at: CGPoint(x: 500, y: 500), metrics: m, limit: 4) == 3)     // clamped to the tiles
    #expect(layout.slot(at: CGPoint(x: -80, y: -80), metrics: m, limit: 6) == 0)
}

@Test func arrowNeighbours() {
    let layout = LauncherLayout(columns: 3, rows: 2)
    #expect(layout.neighbour(of: 0, .down, count: 6) == 1)
    #expect(layout.neighbour(of: 0, .up, count: 6) == nil)
    #expect(layout.neighbour(of: 0, .right, count: 6) == 2)
    #expect(layout.neighbour(of: 3, .left, count: 6) == 1)
    #expect(layout.neighbour(of: 4, .right, count: 6) == nil)
    #expect(layout.neighbour(of: 2, .right, count: 4) == nil)            // no tile there
}
