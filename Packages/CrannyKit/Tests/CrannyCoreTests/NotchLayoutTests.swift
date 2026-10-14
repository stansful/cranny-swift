import CoreGraphics
import Testing
@testable import CrannyCore

// DESIGN.md §3.3: every number in the state-geometry tables, measured on the reference 14″ MacBook Pro
// (notch 185 × 32, screen 1512 pt), the 16″ and an external display (menu bar 30 pt).

private func expect(_ g: NotchGeometry, width: CGFloat, height: CGFloat, bottomRadius: CGFloat? = nil,
                    ear: CGFloat? = nil, outer: CGFloat? = nil, sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(abs(g.bodyWidth - width) < 0.01, "width \(g.bodyWidth) ≠ \(width)", sourceLocation: sourceLocation)
    #expect(abs(g.height - height) < 0.01, "height \(g.height) ≠ \(height)", sourceLocation: sourceLocation)
    if let bottomRadius { #expect(abs(g.bottomRadius - bottomRadius) < 0.01, "r \(g.bottomRadius)", sourceLocation: sourceLocation) }
    if let ear { #expect(abs(g.earRadius - ear) < 0.01, "ear \(g.earRadius)", sourceLocation: sourceLocation) }
    if let outer { #expect(abs(g.outerWidth - outer) < 0.01, "outer \(g.outerWidth)", sourceLocation: sourceLocation) }
}

@Test func referenceMacBookGeometryMatchesTheDesignTable() {
    let l = NotchLayout(metrics: .reference)
    #expect(l.u == 1)
    expect(l.closed, width: 184, height: 31.5, bottomRadius: 10, ear: 0, outer: 184)
    expect(l.hover, width: 196, height: 34.5, bottomRadius: 12, ear: 4, outer: 204)
    expect(l.compact(.glyph), width: 265, height: 32, bottomRadius: 13, ear: 6, outer: 277)
    expect(l.compact(.short), width: 289, height: 32, bottomRadius: 13, ear: 6, outer: 301)
    expect(l.compact(.medium), width: 321, height: 32, bottomRadius: 13, ear: 6, outer: 333)
    expect(l.hud, width: 369, height: 32, bottomRadius: 13, ear: 6, outer: 381)
    expect(l.peek(rows: 1), width: 425, height: 92, bottomRadius: 22, ear: 8, outer: 441)
    expect(l.peek(rows: 2), width: 425, height: 144, bottomRadius: 22, ear: 8, outer: 441)
    expect(l.peek(rows: 9), width: 425, height: 32 + 4 * 52 + 8)                         // at most 4 rows
    expect(l.open(columns: 10), width: 656, height: 170, bottomRadius: 32, ear: 10, outer: 676)
    #expect(l.maxColumns == 12)
    expect(l.open(columns: 12), width: 784, height: 170, outer: 804)
    expect(l.open(columns: 99), width: 784, height: 170)                                  // clamped to max columns
    expect(l.open(columns: l.maxColumns, rows: 3), width: 784, height: 234)              // Notes focus
    expect(l.open(columns: 1), width: 185 + 2 * 160, height: 170)                        // header minimum
    #expect(l.canvasSize == CGSize(width: 900, height: 282))
    #expect(l.closed.topInset == 0 && !l.closed.isFloating)
}

@Test func otherDisplaysMatchTheDesignTable() {
    let sixteen = NotchLayout(metrics: NotchMetrics(hasNotch: true, notchWidth: 185, bandHeight: 32, screenWidth: 1728))
    #expect(sixteen.maxColumns == 13)
    #expect(sixteen.canvasSize == CGSize(width: 964, height: 282))

    let external = NotchMetrics(hasNotch: false, notchWidth: 0, bandHeight: 30, screenWidth: 1920)
    let island = NotchLayout(metrics: external)                                           // floating island (default)
    #expect(island.isFloating && abs(island.u - 0.9375) < 0.0001)
    expect(island.closed, width: 64, height: 5, bottomRadius: 2.5, ear: 0)
    #expect(island.closed.topInset == 4)
    expect(island.compact(.short), width: 110, height: 24, bottomRadius: 12, ear: 0)
    #expect(island.compact(.short).topInset == 3)
    expect(island.hud, width: 184, height: 24)
    expect(island.peek(rows: 1), width: 405, height: 84, bottomRadius: 22, ear: 0)
    expect(island.open(columns: 10), width: 656, height: 168, bottomRadius: 32, ear: 0)
    #expect(island.open(columns: 10).topInset == 6)
    #expect(island.maxColumns == 13)
    #expect(island.canvasSize == CGSize(width: 944, height: 286))

    let attached = NotchLayout(metrics: external, noNotchStyle: .attached)
    expect(attached.closed, width: 64, height: 5, ear: 2)
    expect(attached.compact(.short), width: 110, height: 30)
    expect(attached.hud, width: 184, height: 30)
    expect(attached.peek(rows: 1), width: 405, height: 90)
    #expect(attached.canvasSize == CGSize(width: 963, height: 280))

    #expect(NotchLayout(metrics: external, noNotchStyle: .off).closed == .zero)
}

@Test func panelPaddingTuneKeepsCardsConcentric() {
    for tune in [-4.0, -2.0, 0.0, 3.0, 4.0, 9.0] {
        let grid = NookGrid(paddingTune: CGFloat(tune))
        let clamped = min(max(CGFloat(tune), -4), 4)
        #expect(grid.padding == 12 + clamped)
        #expect(grid.panelRadius == Radius.card + 12 + clamped)
        #expect(grid.cardRadius == Radius.card)                                             // cards stay at r 20
        let open = NotchLayout(metrics: .reference, grid: grid).open(columns: 10)
        #expect(open.bodyWidth == 632 + 2 * (12 + clamped))
        #expect(open.bottomRadius == grid.panelRadius)
        #expect(open.height == 32 + 6 + 120 + 12 + clamped)
    }
    var theme = CrannyTheme()
    theme.panelPaddingTune = 3
    #expect(theme.grid.padding == 15 && theme.grid.panelRadius == 35)
}

@Test func largerTextGrowsTheCellNotTheBand() {
    let xl = NookGrid(textSize: .extraLarge)
    #expect(xl.cell == 68)                                                                  // 56 × 1.24 → 68 (4-pt grid)
    #expect(CrannyTextStyle.compact.pointSize(textSize: .extraLarge, notchUnit: 1) == 13)  // band text follows the notch unit
    #expect(CrannyTextStyle.caption.pointSize(textSize: .small, notchUnit: 1) == 10)       // never below 10 pt
}
