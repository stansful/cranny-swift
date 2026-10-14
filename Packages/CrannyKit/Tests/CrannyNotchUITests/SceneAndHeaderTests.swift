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

/// Every language of the app's String Catalogs: the `.lproj` folders of the package resource bundles beside this
/// module's (a new language is measured as soon as its translations are merged).
nonisolated private let headerLanguages: [String] = {
    let directory = Bundle.module.bundleURL.deletingLastPathComponent()
    let bundles = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
    let codes = bundles
        .filter { $0.lastPathComponent.hasPrefix("CrannyKit_") && $0.pathExtension == "bundle" }
        .compactMap(Bundle.init(url:))
        .flatMap(\.localizations)
    return Set(codes).subtracting(["Base"]).sorted()
}()

/// `key` from `module`'s catalog in `code`, as the app shows it (the key when that bundle lacks the language).
private func catalogText(_ key: String, module: String, _ code: String) -> String {
    let url = Bundle.module.bundleURL.deletingLastPathComponent().appending(path: "CrannyKit_\(module).bundle")
    guard let bundle = Bundle(url: url), let path = bundle.path(forResource: code, ofType: "lproj"),
          let localized = Bundle(path: path) else { return key }
    return localized.localizedString(forKey: key, value: key, table: "Localizable")
}

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

    @Test func everyCatalogLanguageIsMeasured() {
        #expect(headerLanguages.contains("en") && headerLanguages.contains("ru"), "\(headerLanguages)")
    }

    /// One to five pages (Home and the Tray in the language, three long user pages, the Tray with a count), XL text:
    /// the track always fits its side zone, collapsing to icons and then to the selected page plus a menu. The layout
    /// editor's bar takes the other side: "N cells left" shortens to N when the zone is narrow.
    @Test(arguments: headerLanguages) func tabsAlwaysFitTheirZone(code: String) {
        let titles = [catalogText("Home", module: "CrannyNotchUI", code), "Сосредоточение", "Рабочий стол", "Путешествия"]
        let tray = catalogText("Tray", module: "CrannyTray", code)
        let symbols = ["square.grid.2x2.fill", "note.text", "folder", "calendar"]
        let side: CGFloat = 140
        var failures: [String] = []
        for size in [CrannyTextSize.standard, .extraLarge] {
            var theme = CrannyTheme()
            theme.textSize = size
            for count in 1...5 {
                var tabs = (0..<min(count, 4)).map { HeaderTab(id: PageID(rawValue: "p\($0)"), title: titles[$0], symbol: symbols[$0], badge: nil) }
                if count == 5 { tabs.append(HeaderTab(id: .tray, title: tray, symbol: "tray.full.fill", badge: 128)) }
                let host = NSHostingController(rootView: HeaderTabsView(tabs: tabs, selected: tabs[0].id, select: { _ in })
                    .crannyThemeRoot(theme).environment(\.locale, Locale(identifier: code)))
                let width = host.sizeThatFits(in: CGSize(width: side, height: 32)).width
                if width > side { failures.append("\(count) tabs at \(size): \(width) pt") }
            }
        }
        let (model, registry) = previewScene(.open, mode: .editLayout)
        let page = registry.services.settings[CoreSettings.pages][0]
        let bar = NSHostingController(rootView: EditLayoutBar(page: page, model: model, registry: registry, actions: NotchUIActions())
            .crannyThemeRoot(CrannyTheme()).environment(\.locale, Locale(identifier: code)))
        let barWidth = bar.sizeThatFits(in: CGSize(width: side, height: 32)).width
        if barWidth > side { failures.append("the layout editor bar: \(barWidth) pt") }
        #expect(failures.isEmpty, "\(code) («\(titles[0])», «\(tray)»), \(side)-pt zone: \(failures.joined(separator: "; "))")
    }

    @Test func theMenuNamesThePageAndItsCount() {
        #expect(HeaderTabsView.menuTitle(HeaderTab(id: .tray, title: "Tray", symbol: "tray.full.fill", badge: 3)) == "Tray · 3")
    }

    /// The header at its minimum width (N + 2 · 160) with five pages: nothing is drawn in the camera zone.
    @Test func theCameraZoneStaysEmptyAtTheHeaderMinimum() throws {
        let (model, registry) = previewScene(.open)
        registry.services.settings[CoreSettings.pages] += [
            NookPage(id: "page.focus", title: "Сосредоточение", symbol: "note.text", items: []),
            NookPage(id: "page.work", title: "Рабочий стол", symbol: "folder", items: []),
            NookPage(id: "page.trip", title: "Путешествия", symbol: "calendar", items: []),
        ]
        registry.add(page: PageDescriptor(id: .tray, title: "Полка", symbol: "tray.full.fill", order: 10, badge: { 128 }) { _ in
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

    /// What takes the open header: a HUD that leads, else a message of the primary or of the owner's `headerActivity`
    /// (the Pause Live Activities confirmation behind another alert); an activity without a message never does.
    @Test func theHeaderIsTakenByAHUDOrAMessage() throws {
        let hud = PreviewActivity(.hud), media = PreviewActivity(.nowPlaying)
        let confirmation = PreviewConfirmation(PreviewConfirmation.sentence), silent = PreviewConfirmation(nil)
        func resolve(_ primary: (any LiveActivity)?, _ header: (any LiveActivity)?) -> String? {
            HeaderTakeover.resolve(primary: primary.map { ($0.id, $0) }, header: header.map { ($0.id, $0) })?.key
        }
        #expect(resolve(nil, nil) == nil && resolve(media, nil) == nil && resolve(media, silent) == nil)
        #expect(resolve(hud, confirmation) == "hud:\(hud.id.rawValue)")
        #expect(resolve(media, confirmation) == "message:\(confirmation.id.rawValue):\(PreviewConfirmation.sentence)")
        #expect(resolve(confirmation, nil) == resolve(media, confirmation))
        confirmation.headerMessage = ""
        #expect(resolve(media, confirmation) == nil)
    }

    /// The confirmation in the open header: the glyph against the camera zone on the left (the tabs make way), the
    /// sentence against it on the right when it fits the side, else the short word; nothing over the camera.
    @Test(arguments: [false, true]) func aConfirmationTakesTheHeaderRow(atTheMinimum: Bool) throws {
        let (model, registry) = previewScene(.open, headerMessage: PreviewConfirmation.sentence)
        let width = atTheMinimum ? notch.open(columns: 1).bodyWidth - 2 * CrannyTheme().grid.padding : 632
        let zone = NookHeader.cameraZone(notch)
        let view = NookHeader(model: model, registry: registry, actions: NotchUIActions(), select: { _ in }, perform: { _ in })
            .frame(width: width, height: notch.headerHeight)
            .background(Color.black)
            .environment(\.notchRendersFinalState, true)
            .crannyThemeRoot(CrannyTheme())
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        let probe = try #require(renderer.cgImage.flatMap { ShapeProbe($0, scale: 2) })
        func lit(_ x: Int) -> Bool { (0..<probe.height).contains { probe.luminance(x: x, y: $0) > 0.02 } }
        let left = Int((width - zone) / 2 * 2), right = Int((width + zone) / 2 * 2)
        #expect(!(left + 2...right - 2).contains(where: lit), "drawn in the camera zone")
        // Left: only the glyph, against the zone (no tabs further out).
        let leftmost = try #require((0..<left).first(where: lit))
        #expect(CGFloat(left - leftmost) / 2 <= 24, "the left side starts \(CGFloat(left - leftmost) / 2) pt from the zone")
        // Right: the sentence, or the word where the sentence does not fit.
        func measured(_ text: some View) -> CGFloat {
            NSHostingView(rootView: text.fixedSize().crannyThemeRoot(CrannyTheme())).fittingSize.width
        }
        let sentence = measured(Text(verbatim: PreviewConfirmation.sentence).crannyFont(.headline))
        let word = measured(Text(verbatim: "Paused").crannyFont(.compact))
        let side = HeaderRowLayout.sideWidth(width: width, centre: zone)
        let rightmost = try #require((right..<probe.width).last(where: lit))
        let drawn = CGFloat(rightmost - right) / 2
        let expected = sentence <= side ? sentence : word
        #expect(abs(drawn - expected) <= 3, "drew \(drawn) pt, expected \(expected) (sentence \(sentence), side \(side))")
        #expect(atTheMinimum == (sentence > side))                     // both layouts are exercised
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

