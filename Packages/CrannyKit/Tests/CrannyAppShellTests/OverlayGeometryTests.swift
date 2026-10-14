// Pure overlay logic: hover zones (ARCHITECTURE.md §4.3, DESIGN.md §3.6, §4.6), display selection (§4.9),
// full-screen detection (§5.7), the AirDrop anchor (§5.9), type-to-capture keys (§4.10), scroll phases (§5.6),
// dragged content types (§5.5) and the calibration loupe (DESIGN.md §3.1). No windows.
import AppKit
import CrannyCore
import Foundation
import Testing
import UniformTypeIdentifiers
@testable import CrannyAppShell

// MARK: - Hover zones

/// A 1512 × 982 screen with a 32-pt band and the reference closed notch (184 × 31.5) top-centred.
private let screenFrame = CGRect(x: 0, y: 0, width: 1512, height: 982)
private let panelFrame = CGRect(x: 306, y: 700, width: 900, height: 282)
private let closedShape = HoverZones.shapeRect(NotchLayout(metrics: .reference).closed, panelFrame: panelFrame)

private func zones(expanded: Bool = false, satellite: CGRect? = nil, wings: CGRect? = nil) -> HoverZones {
    HoverZones(shape: closedShape, satellite: satellite, wings: wings, screenFrame: screenFrame, band: 32, expanded: expanded)
}

@Test func shapeRectsAreTopCentredInThePanel() {
    #expect(closedShape == CGRect(x: 664, y: 950.5, width: 184, height: 31.5))
    #expect(HoverZones.screenRect(CGRect(x: 10, y: 20, width: 30, height: 40), panelFrame: panelFrame)
            == CGRect(x: 316, y: 922, width: 30, height: 40))
}

@Test func theEntryZoneIsTheShapePlusFourAndReachesAboveTheTopEdge() {
    let z = zones()
    #expect(z.contains(CGPoint(x: 756, y: 982)))                               // y == maxY: the very top row (R1 §2.5)
    #expect(z.contains(CGPoint(x: 661, y: 960)))                               // 3 pt beside the shape
    #expect(!z.contains(CGPoint(x: 658, y: 960)))                              // 6 pt beside it
    #expect(!z.contains(CGPoint(x: 756, y: 944)))                              // 6.5 pt below it
    let open = zones(expanded: true)
    #expect(open.contains(CGPoint(x: 652, y: 960)) && !open.contains(CGPoint(x: 648, y: 960)))   // exit zone: + 14 pt
}

@Test func theSatelliteJoinsTheHoverZone() {
    let satellite = CGRect(x: 860, y: 954, width: 24, height: 24)
    #expect(!zones().contains(CGPoint(x: 872, y: 966)))
    #expect(zones(satellite: satellite).contains(CGPoint(x: 872, y: 966)))
}

@Test func theDragZoneIsWiderAndReachesFortyPointsBelowTheBand() {
    let drag = zones().dragZone
    #expect(drag.minX == closedShape.minX - 80 && drag.maxX == closedShape.maxX + 80)
    #expect(drag.minY == 982 - 32 - 40 && drag.maxY == 983)
    #expect(zones(expanded: true).dragZone == zones(expanded: true).hoverZone)   // over the open panel: its exit zone
}

@Test func theCourtesyZoneIsTheBandBesideTheWings() {
    let wings = CGRect(x: 605, y: 950, width: 301, height: 32)
    let z = zones(wings: wings)
    #expect(z.bandPosition(CGPoint(x: 590, y: 966)) == .courtesy)              // 15 pt left of the wings
    #expect(z.bandPosition(CGPoint(x: 915, y: 966)) == .courtesy)              // 9 pt right
    #expect(z.bandPosition(CGPoint(x: 603, y: 966)) == .band)                  // inside the 4-pt entry inflation
    #expect(z.bandPosition(CGPoint(x: 560, y: 966)) == .band)                  // 45 pt away: just the menu bar
    #expect(z.bandPosition(CGPoint(x: 590, y: 900)) == .outside)
    #expect(zones().bandPosition(CGPoint(x: 590, y: 966)) == .band)            // no wings, no courtesy
}

/// The satellite sits in the courtesy strip: the pointer on it came for the satellite, so the wings stay.
@Test func theSatelliteIsNotMenuBarCourtesy() {
    let wings = CGRect(x: 605, y: 950, width: 301, height: 32)
    let satellite = CGRect(x: 912, y: 954, width: 24, height: 24)
    let z = HoverZones(shape: wings, satellite: satellite, wings: wings, screenFrame: screenFrame, band: 32, expanded: false)
    #expect(z.bandPosition(CGPoint(x: 915, y: 966)) == .band)                  // on the satellite
    #expect(z.bandPosition(CGPoint(x: 590, y: 966)) == .courtesy)              // the other side still retracts
}

@Test func theTrackerReportsOnlyTransitions() {
    let tracker = HoverTracker()
    let z = zones()
    #expect(tracker.update(CGPoint(x: 756, y: 960), zones: z) == [.pointerEntered, .band(.band)])
    #expect(tracker.update(CGPoint(x: 757, y: 961), zones: z).isEmpty)
    #expect(tracker.update(CGPoint(x: 756, y: 500), zones: z) == [.pointerLeft, .band(.outside)])
    #expect(tracker.update(CGPoint(x: 756, y: 960), zones: nil) == [])        // hidden: never "inside"
    #expect(tracker.updateDrag(CGPoint(x: 600, y: 930), zones: z) == true)
    #expect(tracker.updateDrag(CGPoint(x: 601, y: 930), zones: z) == nil)
    #expect(tracker.updateDrag(CGPoint(x: 100, y: 100), zones: z) == false)
}

// MARK: - Display selection (§4.9)

private let builtIn = DisplayDescriptor(key: "built-in", displayID: 1, isBuiltIn: true, hasNotch: true, isPrimary: false)
private let external = DisplayDescriptor(key: "external", displayID: 2, isBuiltIn: false, hasNotch: false, isPrimary: true)
private let side = DisplayDescriptor(key: "side", displayID: 3, isBuiltIn: false, hasNotch: false, isPrimary: false)

private func placed(_ displays: [DisplayDescriptor], _ selection: DisplaySelection,
                    perDisplay: [DisplayKey: DisplayPreferences] = [:], style: NoNotchStyle = .floatingIsland) -> [DisplayKey] {
    DisplayCatalog.placements(for: displays, selection: selection, perDisplay: perDisplay, noNotchStyle: style).map(\.key)
}

@Test func builtInFallsBackToThePrimaryDisplayInClamshell() {
    #expect(placed([external, builtIn, side], .builtIn) == ["built-in"])
    #expect(placed([external, side], .builtIn) == ["external"])                // lid closed: no built-in screen
    #expect(placed([], .builtIn).isEmpty)
}

@Test func allPointerAndCustomSelections() {
    #expect(placed([external, builtIn, side], .all) == ["external", "built-in", "side"])
    #expect(placed([external, builtIn, side], .pointer) == ["external", "built-in", "side"])
    #expect(DisplayCatalog.followsPointer(.pointer) && !DisplayCatalog.followsPointer(.all))
    #expect(placed([external, builtIn, side], .custom(["side", "gone"])) == ["side"])
    #expect(placed([external, builtIn], .custom(["gone"])) == ["external"])    // none connected: the primary
}

@Test func styleOffRemovesOnlyDisplaysWithoutANotch() {
    var off = DisplayPreferences(style: .off)
    off.showsPeeks = false
    #expect(placed([external, builtIn, side], .all, perDisplay: ["side": off]) == ["external", "built-in"])
    #expect(placed([external, builtIn], .all, style: .off) == ["built-in"])     // a hardware notch is always drawn
    let attached = DisplayCatalog.placements(for: [side], selection: .all, perDisplay: ["side": DisplayPreferences(style: .attached)],
                                             noNotchStyle: .floatingIsland)
    #expect(attached == [PanelPlacement(key: "side", style: .attached)])
}

// MARK: - Full screen (§5.7)

private let display = FullScreenDetector.Display(id: 7, bounds: CGRect(x: 0, y: 0, width: 1512, height: 982), notchBand: 32)
private let menuBar = FullScreenDetector.Window(layer: 24, bounds: CGRect(x: 0, y: 0, width: 1512, height: 32), ownerPID: 90, ownerName: "Window Server")
private func appWindow(_ bounds: CGRect, pid: pid_t = 500, layer: Int = 0) -> FullScreenDetector.Window {
    FullScreenDetector.Window(layer: layer, bounds: bounds, ownerPID: pid, ownerName: "App")
}
private let fullBounds = CGRect(x: 0, y: 0, width: 1512, height: 982)
private let belowBand = CGRect(x: 0, y: 32, width: 1512, height: 950)

private func front(_ windows: [FullScreenDetector.Window], frontmost: pid_t? = 500, excluded: Bool = false,
                   ignored: Set<pid_t> = [1]) -> FullScreenDetector.Front {
    FullScreenDetector.evaluate(windows: windows, displays: [display], frontmostPID: frontmost, frontmostIsExcluded: excluded,
                                ignoredPIDs: ignored)[7] ?? FullScreenDetector.Front()
}

@Test func aFrontmostWindowCoveringTheDisplayIsFullScreen() {
    #expect(front([appWindow(fullBounds)], frontmost: 500).fullScreen)
    #expect(!front([menuBar, appWindow(fullBounds)], frontmost: 600).fullScreen)   // another app's, menu bar present
    #expect(front([appWindow(fullBounds)], frontmost: 600).fullScreen)              // … menu bar gone: full screen
    #expect(!front([appWindow(CGRect(x: 0, y: 32, width: 1512, height: 900))]).fullScreen)   // an ordinary big window
    #expect(!front([appWindow(fullBounds, pid: 1)], frontmost: 1).fullScreen)        // Cranny itself (ignored)
    #expect(!front([appWindow(fullBounds, layer: 3)]).fullScreen)                    // not a document window
}

@Test func belowTheNotchCountsOnlyWithoutTheMenuBar() {
    #expect(!front([menuBar, appWindow(belowBand)]).fullScreen)                // a zoomed window on a notched display
    #expect(front([appWindow(belowBand)]).fullScreen)                          // a full-screen app outside the housing
}

@Test func excludedAppsCountOnTheDisplaysTheyAreOn() {
    #expect(front([menuBar, appWindow(CGRect(x: 100, y: 100, width: 600, height: 400))], excluded: true).excludedApp)
    #expect(!front([menuBar, appWindow(CGRect(x: 2000, y: 100, width: 600, height: 400))], excluded: true).excludedApp)
    #expect(!front([menuBar, appWindow(CGRect(x: 100, y: 100, width: 600, height: 400))], excluded: false).excludedApp)
}

/// Two identical displays side by side with aligned tops: the left one's menu bar says nothing about the right
/// one, which shows a full-screen app that is not frontmost (a video while the user works on the left).
@Test func theMenuBarOfAnotherDisplayDoesNotCount() {
    let left = FullScreenDetector.Display(id: 1, bounds: CGRect(x: 0, y: 0, width: 1920, height: 1080), notchBand: 0)
    let right = FullScreenDetector.Display(id: 2, bounds: CGRect(x: 1920, y: 0, width: 1920, height: 1080), notchBand: 0)
    let leftMenuBar = FullScreenDetector.Window(layer: 24, bounds: CGRect(x: 0, y: 0, width: 1920, height: 24), ownerPID: 90,
                                                ownerName: "Window Server")
    let video = appWindow(right.bounds, pid: 700)
    let editor = appWindow(CGRect(x: 100, y: 100, width: 800, height: 600), pid: 500)
    let result = FullScreenDetector.evaluate(windows: [leftMenuBar, editor, video], displays: [left, right], frontmostPID: 500,
                                             frontmostIsExcluded: false, ignoredPIDs: [1])
    #expect(result[2]?.fullScreen == true && result[1]?.fullScreen == false)
    #expect(FullScreenDetector.menuBarHeight(on: right.bounds, windows: [leftMenuBar]) == nil)
    #expect(FullScreenDetector.menuBarHeight(on: left.bounds, windows: [leftMenuBar]) == 24)
}

@Test func theMenuBarHeightComesFromTheWindowServer() {
    #expect(FullScreenDetector.menuBarHeight(on: display.bounds, windows: [menuBar]) == 32)
    #expect(FullScreenDetector.menuBarHeight(on: display.bounds, windows: []) == nil)
    let info: [String: Any] = [kCGWindowLayer as String: 24, kCGWindowOwnerPID as String: 90,
                               kCGWindowOwnerName as String: "Window Server",
                               kCGWindowBounds as String: CGRect(x: 0, y: 0, width: 1512, height: 32).dictionaryRepresentation]
    #expect(FullScreenDetector.window(from: info) == menuBar)
}

// MARK: - Sharing anchor, keys, scroll phases, dragged types, loupe

@Test func theAirDropAnchorSitsUnderTheNotchInsideTheScreen() {
    let visible = CGRect(x: 0, y: 0, width: 1512, height: 950)
    let anchor = SharingPresenter.anchorFrame(below: closedShape, on: visible)
    #expect(anchor.size == SharingPresenter.anchorSize && anchor.midX == closedShape.midX && anchor.maxY <= closedShape.minY)
    let corner = SharingPresenter.anchorFrame(below: CGRect(x: 1490, y: 940, width: 20, height: 10), on: visible)
    #expect(visible.contains(corner))
}

@Test func aSharingSessionEndsOnlyWithNothingLeftOnTheAnchor() {
    #expect(SharingPresenter.sessionLooksOver(anchorHasSheet: false, anchorHasChildren: false))
    #expect(!SharingPresenter.sessionLooksOver(anchorHasSheet: true, anchorHasChildren: false))
    #expect(!SharingPresenter.sessionLooksOver(anchorHasSheet: false, anchorHasChildren: true))
}

// MARK: - Panel frame (§4.9 reconfiguration, §5.1)

private let housing = (left: CGRect(x: 0, y: 950, width: 650, height: 32), right: CGRect(x: 862, y: 950, width: 650, height: 32))

@Test func thePanelIsTopCentredOnTheHousing() {
    let canvas = CGSize(width: 900, height: 282)
    let centred = PanelFramePlan.frame(canvas: canvas, screenFrame: screenFrame, leftArea: housing.left, rightArea: housing.right)
    #expect(centred == CGRect(x: 306, y: 700, width: 900, height: 282))
    let moved = PanelFramePlan.frame(canvas: canvas, screenFrame: screenFrame.offsetBy(dx: -1512, dy: 0), leftArea: nil, rightArea: nil)
    #expect(moved.minX == -1512 + 306 && moved.maxY == 982)
}

/// Clamshell → lid open moves the built-in display from x = −1512 to 0 without changing its size or layout: the
/// panel follows at once, even while open. A new canvas size applies while closed and waits otherwise.
@Test func thePanelFollowsItsDisplayAndResizesOnlyWhileClosed() {
    let canvas = CGSize(width: 900, height: 282)
    let stale = CGRect(x: -1206, y: 700, width: 900, height: 282)               // where it was before the lid opened
    let frame = { (size: CGSize) in PanelFramePlan.frame(canvas: size, screenFrame: screenFrame, leftArea: nil, rightArea: nil) }
    let moved = PanelFramePlan(current: stale, canvas: canvas, layoutChanged: false, isClosed: false, frame: frame)
    #expect(moved == PanelFramePlan(frame: CGRect(x: 306, y: 700, width: 900, height: 282), layout: .unchanged))
    let bigger = CGSize(width: 960, height: 300)
    let open = PanelFramePlan(current: stale, canvas: bigger, layoutChanged: true, isClosed: false, frame: frame)
    #expect(open == PanelFramePlan(frame: CGRect(x: 306, y: 700, width: 900, height: 282), layout: .pending))
    let closed = PanelFramePlan(current: stale, canvas: bigger, layoutChanged: true, isClosed: true, frame: frame)
    #expect(closed == PanelFramePlan(frame: CGRect(x: 276, y: 682, width: 960, height: 300), layout: .apply))
    let density = PanelFramePlan(current: moved.frame, canvas: canvas, layoutChanged: true, isClosed: true, frame: frame)
    #expect(density.layout == .apply && density.frame == moved.frame)          // same canvas, new layout
}

/// A swipe over a peek acts on the row under the fingers (DESIGN.md §4.4, §9.3).
@Test func thePeekRowUnderThePointer() {
    let layout = NotchLayout(metrics: .reference)
    let g = layout.peek(rows: 3)
    let rows: [ActivityID] = ["a", "b", "c"]
    let top = g.topInset + layout.rowHeight
    #expect(GestureRouter.peekRow(at: CGPoint(x: 450, y: top - 2), layout: layout, geometry: g, rows: rows) == nil)   // band row
    #expect(GestureRouter.peekRow(at: CGPoint(x: 450, y: top + 10), layout: layout, geometry: g, rows: rows) == "a")
    #expect(GestureRouter.peekRow(at: CGPoint(x: 450, y: top + NotchLayout.peekRow + 1), layout: layout, geometry: g, rows: rows) == "b")
    #expect(GestureRouter.peekRow(at: CGPoint(x: 450, y: top + 3 * NotchLayout.peekRow + 2), layout: layout, geometry: g, rows: rows) == nil)
}

@Test func typeToCaptureTakesPlainPrintableKeysOnly() {
    #expect(KeyboardRouter.printable("a", modifiers: []) == "a")
    #expect(KeyboardRouter.printable("Ж", modifiers: [.shift]) == "Ж")
    #expect(KeyboardRouter.printable("a", modifiers: [.command]) == nil)
    #expect(KeyboardRouter.printable("a", modifiers: [.option]) == nil)
    #expect(KeyboardRouter.printable(" ", modifiers: []) == nil)
    #expect(KeyboardRouter.printable("\t", modifiers: []) == nil)
    #expect(KeyboardRouter.printable(String(UnicodeScalar(0xF700)!), modifiers: [.function]) == nil)   // ↑
    #expect(KeyboardRouter.isNavigationKey(48) && KeyboardRouter.isNavigationKey(126) && !KeyboardRouter.isNavigationKey(0))
}

@Test func scrollPhasesMapOneToOne() {
    #expect(GestureRouter.swipePhase([]) == [])
    #expect(GestureRouter.swipePhase(.began) == .began)
    #expect(GestureRouter.swipePhase([.changed]) == .changed)
    #expect(GestureRouter.swipePhase([.ended]) == .ended)
    #expect(GestureRouter.swipePhase([.cancelled]) == .cancelled)
    #expect(GestureRouter.swipePhase([.mayBegin]) == .mayBegin)
    #expect(GestureRouter.swipePhase([.stationary]) == .stationary)
}

@Test func draggedFilesAreTypedByExtensionWithoutTouchingTheDisk() {
    #expect(DragDetector.contentType(of: URL(fileURLWithPath: "/tmp/a.pdf")) == .pdf)
    #expect(DragDetector.contentType(of: URL(fileURLWithPath: "/tmp/folder", isDirectory: true)) == .folder)
    #expect(DragDetector.contentType(of: URL(fileURLWithPath: "/tmp/noext")) == .data)
    #expect(DragDetector.unique([.pdf, .png, .pdf]) == [.pdf, .png])
    let text = DragDetector.contents(types: [.string], pasteboard: nil)
    #expect(!text.hasFiles)                                                    // a text drag never opens the catch state
    #expect(DragDetector.contents(types: [.fileURL], pasteboard: nil) == DragDetector.Contents(hasFiles: true, types: [.item]))
}

@Test func theLoupeSitsBesideTheCornerInsideTheCanvas() {
    let layout = NotchLayout(metrics: .reference)
    let canvas = CGRect(origin: .zero, size: layout.canvasSize)
    let corner = CalibrationOverlay.corner(of: layout.closed, in: canvas)
    #expect(corner == CGPoint(x: canvas.midX + 92, y: 31.5))
    let origin = CalibrationOverlay.loupeOrigin(for: layout.closed, in: canvas)
    #expect(origin.width >= corner.x && origin.height >= corner.y)
    #expect(origin.width + CalibrationOverlay.loupeDiameter <= canvas.maxX && origin.height + CalibrationOverlay.loupeDiameter <= canvas.maxY)
}
