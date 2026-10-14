// The render contract's additions (middle label width, visibility), the header (tabs, hit targets, clock),
// the satellite's place and the open panel's final layout.
import CrannyCore
import Foundation
import SwiftUI
import Testing
@testable import CrannyNotchUI

private let island = NotchLayout(metrics: PreviewDisplays.external)
private let attached = NotchLayout(metrics: PreviewDisplays.external, noNotchStyle: .attached)
private let notch = NotchLayout(metrics: .reference)

@MainActor @Suite("Middle label (open issue 3)") struct MiddleLabelTests {
    @Test func measuredOnlyWithoutANotch() {
        #expect(MiddleLabelMetrics.width(of: "Midnight Window", layout: notch) == 0)
        #expect(MiddleLabelMetrics.width(of: nil, layout: island) == 0)
        #expect(MiddleLabelMetrics.width(of: "   ", layout: island) == 0)
        #expect(MiddleLabelMetrics.width(of: "Hi", layout: NotchLayout(metrics: PreviewDisplays.external, noNotchStyle: .off)) == 0)
        let short = MiddleLabelMetrics.width(of: "Midnight Window", layout: island)
        #expect(short > 60 && short < 140 && short == short.rounded(.up))
        #expect(MiddleLabelMetrics.width(of: "Midnight Window", layout: attached) == short)
        #expect(MiddleLabelMetrics.width(of: String(repeating: "Very long title ", count: 8), layout: island) == 160)
    }

    @Test func widensTheCompactGeometry() {
        let model = NotchSceneModel(layout: island, theme: CrannyTheme())
        model.phase = .compact
        #expect(model.geometry.bodyWidth == 110)                           // 12-pt gap + 2 × 49 (DESIGN.md §3.3)
        model.middleLabelWidth = 96
        #expect(model.geometry.bodyWidth == 194)                           // the label + 2 × 49
        model.layout = notch
        #expect(model.geometry.bodyWidth == 289)                           // the camera is the middle on a notch
        #expect(model.isVisibleOnScreen)
    }
}

@MainActor @Suite("Header (DESIGN.md §6.2)") struct HeaderTests {
    @Test func tabsAreGridPagesThenModulePages() {
        let pages = [NookPage(id: .nook, symbol: "square.grid.2x2.fill", items: []),
                     NookPage(id: "page.focus", title: "Focus", symbol: "note.text", items: [])]
        let tray = PageDescriptor(id: .tray, title: "Tray", symbol: "tray.full.fill", order: 10, badge: { 3 }) { _ in AnyView(EmptyView()) }
        let other = PageDescriptor(id: "x", title: "X", symbol: "folder", order: 1, badge: { 0 }) { _ in AnyView(EmptyView()) }
        let tabs = HeaderTabItems.make(pages: pages, modulePages: [tray, other])
        #expect(tabs.map(\.id) == [.nook, "page.focus", "x", .tray])
        #expect(tabs[0].title == String(localized: "Home", bundle: .module, comment: "Open panel: the built-in widget page (tab)"))
        #expect(tabs[1].title == "Focus")
        #expect(tabs[3].badge == 3 && tabs[2].badge == nil)                // a zero count shows no badge
    }

    @Test func iconButtonsAre28WithA32By24HitArea() {
        // Open issue 4 (design owner): the glyph button stays 28 pt; the tap area is at least 32 × 24.
        #expect(HeaderIconButtonStyle.visual == 28)
        #expect(HeaderIconButtonStyle.hitArea.width >= HitTarget.band.width)
        #expect(HeaderIconButtonStyle.hitArea.height >= HitTarget.band.height)
        #expect(NookHeader.cameraZone(notch) == 201)                       // N + 16 stays empty
    }

    @Test func clockWakesOnTheMinute() throws {
        let utc = try #require(TimeZone(identifier: "UTC"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        let date = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 14, hour: 10, minute: 29, second: 41)))
        let next = MinuteClock.nextMinute(after: date, calendar: calendar)
        #expect(calendar.dateComponents([.hour, .minute, .second], from: next) == DateComponents(hour: 10, minute: 30, second: 0))
    }
}

@MainActor @Suite("Satellite and open layout") struct PlacementTests {
    @Test func satelliteSitsSixUnitsBeyondTheCompactBody() {
        let compact = notch.compact(.short)
        let frame = SatellitePlacement.frame(layout: notch, compact: compact)
        #expect(frame.width == 24 && frame.height == 24)                  // Ø 24u
        #expect(frame.minX == compact.bodyWidth / 2 + 6)                   // 6u beyond the trailing edge (from centre)
        #expect(frame.midY == 16)                                          // centred in the 32-pt band
        #expect(SatellitePlacement.budTravel(layout: notch, compact: compact) == 30)   // 6u gap + Ø
        let islandFrame = SatellitePlacement.frame(layout: island, compact: island.compact(.short))
        #expect(abs(islandFrame.midY - 15) < 0.01)                         // in the pill (inset 3, row 24)
    }

    @Test func openContentIsLaidOutAtTheFinalSize() {
        let model = NotchSceneModel(layout: notch, theme: CrannyTheme())
        model.phase = .open
        model.openColumns = 10
        model.open = OpenState(page: .nook, reason: .click)
        #expect(NookView.finalShape(model) == notch.open(columns: 10))
        #expect(NookView.gridAreaHeight(model, grid: CrannyTheme().grid) == 120)
        model.open = OpenState(page: .nook, mode: .focus(.notes), reason: .click)
        #expect(NookView.finalShape(model).height == 234)
        #expect(NookView.gridAreaHeight(model, grid: CrannyTheme().grid) == 184)   // 3 × 56 + 2 × 8
        // A gesture or a gulp changes the drawn shape, never the content's layout size.
        let drawn = CanvasGeometry.adjusted(model.geometry, phase: .open, gesture: CGSize(width: 0, height: -15), gulp: -3)
        #expect(drawn.height == 216 && NookView.finalShape(model).height == 234)
    }

    @Test func cardChromeHeights() {
        let grid = CrannyTheme().grid
        #expect(CardChrome.height(rows: 2, grid: grid) == 120)
        #expect(CardChrome.height(rows: 3, grid: grid) == 184)
    }
}

