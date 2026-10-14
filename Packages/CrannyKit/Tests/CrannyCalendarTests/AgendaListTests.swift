import CoreGraphics
import Foundation
import Testing
@testable import CrannyCalendar

/// The widget list's geometry (DESIGN.md §7.2): three rows fit under the header at the default size, the fade
/// covers only a row that is cut off, "+N more" counts rows not fully visible, and the list scrolls only when a
/// featured row would be clipped — without leaving a sliver of the row above.
@Suite struct AgendaListTests {
    /// The list's height at 3 cells: 96 content − 16 header − 6 spacing.
    private let viewport: CGFloat = 74

    private func rows(_ spec: [(String, Bool)]) -> [(id: String, frame: RowFrame)] {
        var top: CGFloat = 0
        return spec.map { id, featured in
            let height = featured ? AgendaScroll.featuredHeight : AgendaScroll.rowHeight
            defer { top += height + AgendaScroll.spacing }
            return (id, RowFrame(minY: top, maxY: top + height))
        }
    }

    @Test func threeRowsFitAtTheDefaultSize() {
        // DESIGN.md §7.2 anatomy: a row, the live event on two lines, a row.
        let list = rows([("a", false), ("live", true), ("b", false)])
        #expect((list.last?.frame.maxY ?? 0) <= viewport)
        let layout = ListLayout(rows: list, viewport: viewport, contentTop: 0)
        #expect(layout.top == .init() && layout.bottom == .init())
        #expect(layout.hiddenBelow.isEmpty)
    }

    @Test func fadesCoverOnlyRowsThatAreCutOff() {
        let list = rows([("a", false), ("live", true), ("b", false), ("c", false), ("d", false)])
        // At the top: a, live, b are fully visible (0…72); c starts at 74 — hidden, nothing cut, no fade.
        let top = ListLayout(rows: list, viewport: viewport, contentTop: 0)
        #expect(top.bottom == .init())
        #expect(top.hiddenBelow == ["c", "d"])
        // Scrolled by 10: 8 pt of a remain at the top — a sliver, hidden; 10 pt of c at the bottom — a peek, faded.
        let scrolled = ListLayout(rows: list, viewport: viewport, contentTop: -10)
        #expect(scrolled.top == .init(hidden: 8))
        #expect(scrolled.bottom == .init(fade: 10))
        #expect(scrolled.hiddenBelow == ["c", "d"])
        // Two featured rows fill 66 of 74 pt: 6 pt of the next row would be a smudge — hidden.
        let deep = ListLayout(rows: rows([("live", true), ("next", true), ("x", true)]), viewport: viewport, contentTop: 0)
        #expect(deep.bottom == .init(hidden: 6))
        // A long cut is faded over 12 pt only; fully visible rows are never faded.
        let tall = ListLayout(rows: rows([("live", true), ("x", true)]), viewport: 50, contentTop: 0)
        #expect(tall.bottom == .init(fade: 12))
        #expect(tall.top == .init())
    }

    @Test func noScrollWhenTheFeaturedRowIsVisible() {
        // An all-day event and an ended one above the live meeting: 0…18, 20…38, 40…72 — all fit.
        let list = rows([("holiday", false), ("ended", false), ("live", true), ("later", false)])
        #expect(AgendaScroll.target(rows: list, featured: ["live"], viewport: viewport) == nil)
    }

    @Test func scrollsJustFarEnoughWithoutASliver() throws {
        // Two featured rows (live + soon) after two rows: they end at 106, so the list must scroll by 32. That
        // would leave 6 pt of "ended" above — a sliver — so it scrolls on to the live row's top instead.
        let list = rows([("holiday", false), ("ended", false), ("live", true), ("soon", true), ("lunch", false)])
        let target = try #require(AgendaScroll.target(rows: list, featured: ["live", "soon"], viewport: viewport))
        #expect(target.id == "live")
        #expect(target.anchor == .top)
        let after = ListLayout(rows: list, viewport: viewport, contentTop: -40)
        #expect(after.top == .init())                                        // no sliver above
        #expect(after.bottom == .init(hidden: 6))                            // nor below
        #expect(after.hiddenBelow == ["lunch"])

        // Three rows above one featured row: scrolling by 18 shows the rest of the list from a row boundary
        // (0…18 hides "a" exactly) — bottom-aligned on the featured row.
        let three = rows([("a", false), ("b", false), ("c", false), ("live", true)])
        let bottom = try #require(AgendaScroll.target(rows: three, featured: ["live"], viewport: viewport))
        #expect(bottom.id == "live")
        #expect(bottom.anchor == .bottom)

        // A peek of at least 10 pt stays: it reads as "more above". In an 80-pt list the featured rows end at 106,
        // so the list scrolls by 26 and 12 pt of "b" remain above, faded.
        let peek = rows([("a", false), ("b", false), ("live", true), ("soon", true)])
        let kept = try #require(AgendaScroll.target(rows: peek, featured: ["live", "soon"], viewport: 80))
        #expect(kept.id == "soon" && kept.anchor == .bottom)
        #expect(ListLayout(rows: peek, viewport: 80, contentTop: -26).top == .init(fade: 12))
    }

    @Test func framesFollowTheRowHeights() {
        let agenda = Agenda(day: DateInterval(start: T.date(h: 0), duration: 86_400), isToday: true,
                            rows: [.init(event: T.event("a", start: T.date(h: 9)), role: .ended),
                                   .init(event: T.event("b", start: T.date(h: 10)), role: .live),
                                   .init(event: T.event("c", start: T.date(h: 11)), role: .upcoming)],
                            featuredIDs: ["b"])
        let frames = AgendaScroll.frames(agenda)
        #expect(frames.map(\.frame) == [RowFrame(minY: 0, maxY: 18), RowFrame(minY: 20, maxY: 52), RowFrame(minY: 54, maxY: 72)])
    }
}
