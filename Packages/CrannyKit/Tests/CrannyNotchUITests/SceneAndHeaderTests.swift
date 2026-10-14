// The render contract's additions (middle label width, visibility), the header (tabs, hit targets, clock),
// the satellite's place and the open panel's final layout.
import AppKit
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

    /// The helper measures what MiddleLabel draws: `compactLabel` is SF Rounded with monospaced digits, so a
    /// label with digits measured with proportional digits came out too narrow and was truncated.
    @Test(arguments: ["Track 11", "1111", "Song 2011 (Remastered 2021)", "Midnight Window", "in 4m · 10:30"])
    func measuresTheDrawnFont(label: String) {
        var theme = CrannyTheme()
        theme.notchUnit = island.u
        let host = NSHostingView(rootView: Text(verbatim: label).crannyFont(.compactLabel).fixedSize().crannyThemeRoot(theme))
        let drawn = min(host.fittingSize.width, MiddleLabelMetrics.maximumWidth)    // longer labels truncate at 160
        let measured = MiddleLabelMetrics.width(of: label, layout: island)
        #expect(measured >= drawn - 0.01, "\(label): measured \(measured) < drawn \(drawn)")
        #expect(measured - drawn < 1.01, "\(label): measured \(measured), drawn \(drawn)")
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

    @Test func theCentreIsAlwaysInTheMiddle() {
        #expect(HeaderRowLayout.sideWidth(width: 481, centre: 201) == 140)       // 14″ header minimum: 505 − 2 × 12
        #expect(HeaderRowLayout.sideWidth(width: 632, centre: 201) == 215.5)     // default 10-cell page
        #expect(HeaderRowLayout.sideWidth(width: 100, centre: 201) == 0)
    }

    /// One to five pages (Home, three user pages, the Tray with a count), long titles, XL text: the track
    /// always fits its side zone, collapsing to icons and then to the selected page plus a menu.
    @Test func tabsAlwaysFitTheirZone() {
        let titles = ["Главная", "Сосредоточение", "Рабочий стол", "Путешествия"]
        let symbols = ["square.grid.2x2.fill", "note.text", "folder", "calendar"]
        for size in [CrannyTextSize.standard, .extraLarge] {
            var theme = CrannyTheme()
            theme.textSize = size
            for count in 1...5 {
                var tabs = (0..<min(count, 4)).map { HeaderTab(id: PageID(rawValue: "p\($0)"), title: titles[$0], symbol: symbols[$0], badge: nil) }
                if count == 5 { tabs.append(HeaderTab(id: .tray, title: "Лоток", symbol: "tray.full.fill", badge: 128)) }
                let host = NSHostingController(rootView: HeaderTabsView(tabs: tabs, selected: tabs[0].id, select: { _ in })
                    .crannyThemeRoot(theme))
                let side: CGFloat = 140
                let width = host.sizeThatFits(in: CGSize(width: side, height: 32)).width
                #expect(width <= side, "\(count) tabs at \(size): \(width) pt in a \(side)-pt zone")
            }
        }
        #expect(HeaderTabsView.menuTitle(HeaderTab(id: .tray, title: "Tray", symbol: "tray.full.fill", badge: 3)) == "Tray · 3")
        // The layout editor's bar takes the other side: "N cells left" shortens to N when the zone is narrow.
        let (model, registry) = previewScene(.open, mode: .editLayout)
        let page = registry.services.settings[CoreSettings.pages][0]
        let bar = NSHostingController(rootView: EditLayoutBar(page: page, model: model, registry: registry, actions: NotchUIActions())
            .crannyThemeRoot(CrannyTheme()))
        #expect(bar.sizeThatFits(in: CGSize(width: 140, height: 32)).width <= 140)
    }

    /// The header at its minimum width (N + 2 · 160) with five pages: nothing is drawn in the camera zone.
    @Test func theCameraZoneStaysEmptyAtTheHeaderMinimum() throws {
        let (model, registry) = previewScene(.open)
        registry.services.settings[CoreSettings.pages] += [
            NookPage(id: "page.focus", title: "Сосредоточение", symbol: "note.text", items: []),
            NookPage(id: "page.work", title: "Рабочий стол", symbol: "folder", items: []),
            NookPage(id: "page.trip", title: "Путешествия", symbol: "calendar", items: []),
        ]
        registry.add(page: PageDescriptor(id: .tray, title: "Лоток", symbol: "tray.full.fill", order: 10, badge: { 128 }) { _ in
            AnyView(EmptyView())
        })
        let width = notch.open(columns: 1).bodyWidth - 2 * CrannyTheme().grid.padding
        let zone = NookHeader.cameraZone(notch)
        let view = NookHeader(model: model, registry: registry, actions: NotchUIActions(), select: { _ in }, perform: { _ in })
            .frame(width: width, height: notch.headerHeight)
            .background(Color.black)
            .environment(\.notchRendersFinalState, true)
            .crannyThemeRoot(CrannyTheme())
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        let probe = try #require(renderer.cgImage.flatMap { ShapeProbe($0, scale: 2) })
        let first = Int(((width - zone) / 2 + 1) * 2), last = Int(((width + zone) / 2 - 1) * 2)
        var lit = 0
        for y in 0..<probe.height { for x in first...last where probe.luminance(x: x, y: y) > 0.02 { lit += 1 } }
        #expect(lit == 0, "\(lit) pixels drawn in the camera zone")
        // … and the tabs are there, left of it.
        #expect((0..<first).contains { x in probe.luminance(x: x, y: probe.height / 2) > 0.02 })
    }

    @Test func clockWakesOnTheMinute() throws {
        let utc = try #require(TimeZone(identifier: "UTC"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        let date = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 14, hour: 10, minute: 29, second: 41)))
        let next = AlignedClock<EmptyView>.nextTick(after: date, anchor: Date(timeIntervalSinceReferenceDate: 0))
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

    @Test func satelliteClickTargetIsABandTarget() {
        for layout in [notch, island, attached] {
            let compact = layout.compact(.short)
            let canvas = CGRect(origin: .zero, size: layout.canvasSize)
            let bubble = layout.satelliteFrame(beside: compact, in: canvas)
            let hit = SatelliteMetrics.hitFrame(beside: compact, layout: layout, in: canvas)
            #expect(hit.width >= HitTarget.band.width && hit.height >= HitTarget.band.height)     // ≥ 32 × 24
            #expect(hit.contains(bubble))
            #expect(abs(hit.midX - bubble.midX) < 0.001 && abs(hit.midY - bubble.midY) < 0.001)
            #expect(SatelliteMetrics.hitSize(layout: layout) == hit.size)
        }
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

