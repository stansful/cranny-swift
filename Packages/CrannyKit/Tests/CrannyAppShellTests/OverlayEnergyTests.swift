// What the pointer, drag and swipe paths no longer do on every event, and that the results stay the same
// (ARCHITECTURE.md §5.5–§5.6, §9.2): the drag detector reads the drag pasteboard only near a panel and keeps its
// baseline across drags elsewhere and across a paused pointer, the pointer pauses only where it can change nothing,
// a panel's hover zones are kept between changes, the drop router reads a session's pasteboard once, and the swipe
// settings follow the settings store by observation. No windows by default; one opt-in check drives a real panel.
import AppKit
import CoreGraphics
@testable import CrannyCore
import CrannyNotchUI
import Foundation
import Testing
import UniformTypeIdentifiers
@testable import CrannyAppShell

// MARK: - Drag detector

/// A private drag pasteboard; `write` puts one file URL on it, as a drag source does when its drag begins. Each test
/// releases it when done.
@MainActor private final class TestDragPasteboard {
    let pasteboard = NSPasteboard(name: NSPasteboard.Name("cranny.test.drag.\(UUID().uuidString)"))
    func write(_ path: String) {
        pasteboard.clearContents()
        pasteboard.writeObjects([URL(fileURLWithPath: path) as NSURL])
    }
    func writeText() {
        pasteboard.clearContents()
        pasteboard.setString("selected text", forType: .string)
    }
    func release() { pasteboard.releaseGlobally() }
}

private let pdfDrag = DragDetector.Contents(hasFiles: true, types: [.pdf])

/// A file drag that never comes near a panel is never inspected and ends without a drag end; what it wrote still
/// joins the baseline, so a later drag near the notch that writes nothing (a window moved by its title bar) is no
/// file drag, and a file drag that comes near is caught on the event it enters.
@Test func aDragFarFromEveryPanelIsNotInspectedAndLeavesNothingBehind() {
    let drag = TestDragPasteboard()
    defer { drag.release() }
    let detector = DragDetector(pasteboard: drag.pasteboard)

    drag.write("/tmp/far-away.pdf")                                              // Finder to Finder, low on the screen
    for _ in 0..<3 { #expect(detector.update(.dragged, nearPanel: false) == nil) }
    #expect(detector.current == nil)
    #expect(detector.update(.up, nearPanel: false) == nil)                      // nothing started: nothing ends

    for _ in 0..<3 { #expect(detector.update(.dragged, nearPanel: true) == nil) }   // the window drag near the notch
    #expect(detector.update(.up, nearPanel: false) == nil && detector.current == nil)

    drag.write("/tmp/report.pdf")                                               // a file drag towards the notch
    #expect(detector.update(.dragged, nearPanel: false) == nil)
    #expect(detector.update(.dragged, nearPanel: true) == .some(pdfDrag))       // inspected where it enters
    #expect(detector.current == pdfDrag)
    #expect(detector.update(.dragged, nearPanel: false) == nil)                 // one inspection per mouse-down
    #expect(detector.update(.moved, nearPanel: false) == .some(nil))            // the button is up: it ended
}

/// A drag near the notch is judged by what it wrote: text is no file drag, and after a drop on our own panel the next
/// drag that writes nothing is none either.
@Test func aDragNearThePanelIsJudgedByItsOwnWrite() {
    let drag = TestDragPasteboard()
    defer { drag.release() }
    let detector = DragDetector(pasteboard: drag.pasteboard)
    #expect(detector.update(.dragged, nearPanel: true) == nil)                  // the source has not written yet
    drag.writeText()
    #expect(detector.update(.dragged, nearPanel: true) == nil)                  // text: inspected, no file drag
    #expect(detector.update(.moved, nearPanel: false) == nil)
    drag.write("/tmp/photo.pdf")
    #expect(detector.update(.dragged, nearPanel: true) == .some(pdfDrag))
    detector.reset()                                                            // dropped on our panel
    #expect(detector.update(.up, nearPanel: false) == nil && detector.current == nil)
    #expect(detector.update(.dragged, nearPanel: true) == nil)                  // the next drag wrote nothing
}

/// A drop on our own panel that the detector never inspected (the drop router alone saw it, over the panel) settles
/// the baseline at once: a next drag that begins before any up or move and writes nothing is no file drag.
@Test func aDropOnThePanelSettlesTheBaseline() {
    let drag = TestDragPasteboard()
    defer { drag.release() }
    let detector = DragDetector(pasteboard: drag.pasteboard)
    drag.write("/tmp/dropped.pdf")
    #expect(detector.update(.dragged, nearPanel: false) == nil)                 // never within a drag zone
    detector.reset()                                                            // dropped; no up or move follows
    #expect(detector.awaitsInspection)
    #expect(detector.update(.dragged, nearPanel: true) == nil)                  // the next drag wrote nothing
    drag.write("/tmp/report.pdf")
    #expect(detector.update(.dragged, nearPanel: true) == .some(pdfDrag))       // a write of its own is caught
    #expect(!detector.awaitsInspection)                                         // once per mouse-down
}

/// Drags made while the pointer was paused: their presses settle the baseline (every earlier drag is over), so a
/// drag still in progress when the pointer resumes is judged by its own write, and with every button up the
/// baseline takes everything written meanwhile.
@Test func dragsMadeWhilePausedKeepTheBaseline() {
    let drag = TestDragPasteboard()
    defer { drag.release() }
    let detector = DragDetector(pasteboard: drag.pasteboard)

    detector.pressedWhilePaused()
    drag.write("/tmp/in-the-game.pdf")                                         // a file drag while hidden
    detector.resumed(buttonsDown: false)
    #expect(detector.update(.dragged, nearPanel: true) == nil)                  // a later window drag: no catch

    #expect(detector.update(.up, nearPanel: false) == nil)
    detector.pressedWhilePaused()                                               // this press's drag is in progress …
    drag.write("/tmp/report.pdf")
    detector.resumed(buttonsDown: true)                                         // … when the panel shows again
    #expect(detector.update(.dragged, nearPanel: true) == .some(pdfDrag))       // caught when it comes near
    #expect(detector.update(.up, nearPanel: false) == .some(nil))

    detector.pressedWhilePaused()
    drag.write("/tmp/earlier.pdf")                                             // a drag that ended while paused
    detector.pressedWhilePaused()                                               // a window drag in progress …
    detector.resumed(buttonsDown: true)
    #expect(detector.update(.dragged, nearPanel: true) == nil)                  // … is no file drag
}

// MARK: - Pausing the pointer

@Test func thePointerPausesOnlyWhereItCanChangeNothing() {
    let visible = NotchEnvironment()
    let locked = NotchEnvironment(isLocked: true)
    let asleep = NotchEnvironment(displaysAsleep: true)
    let hideAllGame = NotchEnvironment(fullScreen: true, policy: .hideAll)
    let hideAllExcluded = NotchEnvironment(excludedApp: true, policy: .hideAll)
    #expect(OverlayCoordinator.pointerCanPause(displays: 1, panels: [NotchEnvironment]()))   // no panel at all
    for hidden in [locked, asleep, hideAllGame, hideAllExcluded] {
        #expect(OverlayCoordinator.pointerCanPause(displays: 1, panels: [hidden]))
    }
    #expect(!OverlayCoordinator.pointerCanPause(displays: 1, panels: [visible]))
    // Alerts only behind a full-screen app, Demo mode, another display's turn under `.pointer`: the panel can show.
    #expect(!OverlayCoordinator.pointerCanPause(displays: 1, panels: [NotchEnvironment(fullScreen: true, policy: .alertsAndHUD)]))
    #expect(!OverlayCoordinator.pointerCanPause(displays: 1, panels: [NotchEnvironment(fullScreen: true, policy: .hideAll,
                                                                                      demoMode: true)]))
    #expect(!OverlayCoordinator.pointerCanPause(displays: 1, panels: [NotchEnvironment(notThisDisplay: true)]))
    // Two displays: the pointer still picks the alert display, so it is never paused.
    #expect(!OverlayCoordinator.pointerCanPause(displays: 2, panels: [locked, locked]))
    #expect(!OverlayCoordinator.pointerCanPause(displays: 2, panels: [NotchEnvironment]()))
    #expect(!OverlayCoordinator.pointerCanPause(displays: 0, panels: [NotchEnvironment]()))
}

/// Pausing needs a started monitor; pause and resume each act once (NSEvent monitors; the tap: PointerTapTests).
@Test func thePointerMonitorPausesAndResumesOnce() {
    _ = NSApplication.shared
    let monitor = PointerMonitor(tapSystem: nil)
    var presses = 0
    monitor.pause { presses += 1 }
    #expect(!monitor.isPaused)                                                  // never started: nothing to pause
    var events = 0
    monitor.start { _, _ in events += 1 }
    #expect(events == 1)                                                        // the pointer resting where it is
    monitor.pause { presses += 1 }
    monitor.pause { presses += 1 }
    #expect(monitor.isPaused && monitor.currentSpeed == 0)
    monitor.resume()
    #expect(!monitor.isPaused && events == 1 && presses == 0)                   // resuming reports nothing by itself
    monitor.resume()
    #expect(!monitor.isPaused)
    monitor.stop()
}

// MARK: - Hover zones between changes

@Test func aPanelsZonesAreKeptUntilTheyCanChange() {
    let layout = NotchLayout(metrics: .reference)
    let screenFrame = CGRect(x: 0, y: 0, width: 1512, height: 982)
    let panelFrame = CGRect(x: 456, y: 782, width: 600, height: 200)
    let zones = HoverZones(shape: HoverZones.shapeRect(layout.closed, panelFrame: panelFrame), satellite: nil, wings: nil,
                           screenFrame: screenFrame, band: layout.band, expanded: false)
    var cache = PanelZonesCache()
    #expect(cache.zones(panelFrame: panelFrame, screenFrame: screenFrame) == nil)              // nothing built yet
    cache.store(zones, panelFrame: panelFrame, screenFrame: screenFrame)
    #expect(cache.zones(panelFrame: panelFrame, screenFrame: screenFrame) == .some(zones))
    #expect(cache.zones(panelFrame: panelFrame.offsetBy(dx: 10, dy: 0), screenFrame: screenFrame) == nil)   // moved
    #expect(cache.zones(panelFrame: panelFrame, screenFrame: screenFrame.insetBy(dx: 1, dy: 0)) == nil)     // display
    cache.invalidate()                                                                          // a sync, a new layout
    #expect(cache.zones(panelFrame: panelFrame, screenFrame: screenFrame) == nil)
    cache.store(nil, panelFrame: panelFrame, screenFrame: screenFrame)                          // hidden: no zones
    #expect(cache.zones(panelFrame: panelFrame, screenFrame: screenFrame) == .some(nil))
}

// MARK: - Window list: only the layers the full-screen heuristic reads

@Test func theWindowSnapshotKeepsOnlyWhatTheHeuristicReads() {
    // Layer 0 and the menu bar's layer only; the owner's name only where `isMenuBar` compares it.
    for window in FullScreenDetector.snapshot() {
        #expect(window.layer == 0 || window.layer == FullScreenDetector.menuBarLayer)
        #expect(window.layer == FullScreenDetector.menuBarLayer || window.ownerName.isEmpty)
    }
    let document: [String: Any] = [kCGWindowLayer as String: 0, kCGWindowOwnerPID as String: 500,
                                   kCGWindowOwnerName as String: "Finder",
                                   kCGWindowBounds as String: CGRect(x: 0, y: 0, width: 1512, height: 982).dictionaryRepresentation]
    #expect(FullScreenDetector.window(from: document)
        == FullScreenDetector.Window(layer: 0, bounds: CGRect(x: 0, y: 0, width: 1512, height: 982), ownerPID: 500, ownerName: ""))
    #expect(FullScreenDetector.window(from: [kCGWindowLayer as String: 0]) == nil)          // no owner or bounds
}

// MARK: - Drop router: one pasteboard read per session

/// The parts of a dragging session the router reads, with its own sequence number.
private final class SessionDraggingInfo: NSObject, NSDraggingInfo {
    let draggingPasteboard: NSPasteboard
    let draggingSequenceNumber: Int
    let draggingLocation = NSPoint(x: 50, y: 150)

    init(pasteboard: NSPasteboard, sequence: Int) {
        draggingPasteboard = pasteboard; draggingSequenceNumber = sequence
    }

    var draggingSource: Any? { nil }
    var draggingSourceOperationMask: NSDragOperation { [.copy, .generic] }
    var draggingDestinationWindow: NSWindow? { nil }
    var draggedImageLocation: NSPoint { .zero }
    var draggedImage: NSImage? { nil }
    func slideDraggedImage(to screenPoint: NSPoint) {}
    var draggingFormation: NSDraggingFormation = .default
    var animatesToDestination = false
    var numberOfValidItemsForDrop = 1
    func enumerateDraggingItems(options enumOpts: NSDraggingItemEnumerationOptions = [], for view: NSView?, classes classArray: [AnyClass],
                                searchOptions: [NSPasteboard.ReadingOptionKey: Any] = [:],
                                using block: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void) {}
    var springLoadingHighlight: NSSpringLoadingHighlight { .none }
    func resetSpringLoading() {}
}

/// Each pointer move over the panel during a drag updates the zones with the contents read on the session's first
/// update (the test rewrites the pasteboard mid-session only to see whether it is read again); a new session reads
/// its own, and a drop of plain file URLs delivers them with the types their drag found.
@Test func theDropRouterReadsASessionsPasteboardOnce() async throws {
    let registry = ModuleRegistry(services: .preview())
    let scene = NotchSceneModel(layout: NotchLayout(metrics: .reference), theme: CrannyTheme())
    let viewModel = NotchViewModel(scene: scene, registry: registry)
    viewModel.pointerKeys = { (false, false) }
    let router = DropRouter(scene: scene, viewModel: viewModel, registry: registry)
    let view = NSView(frame: CGRect(x: 0, y: 0, width: 400, height: 200))
    let drag = TestDragPasteboard()
    defer { drag.release() }
    viewModel.send(.open(page: nil, focus: nil, reason: .click))

    drag.write("/tmp/cranny-test-report.pdf")
    let first = SessionDraggingInfo(pasteboard: drag.pasteboard, sequence: 41)
    #expect(router.dragUpdated(first, in: view) == .copy)
    #expect(scene.zones.draggedTypes == [.pdf] && viewModel.state.fileDrag == [.pdf])
    drag.write("/tmp/cranny-test-photo.png")
    #expect(router.dragUpdated(first, in: view) == .copy)
    #expect(scene.zones.draggedTypes == [.pdf])                                 // not read again
    router.dragExited()
    router.dragEnded()

    let second = SessionDraggingInfo(pasteboard: drag.pasteboard, sequence: 42)
    #expect(router.dragUpdated(second, in: view) == .copy)
    #expect(scene.zones.draggedTypes == [.png])                                 // a new session reads its own

    var received: DropPayload?
    scene.zones.setDropZone(NotchZones.DropZone(id: "test.keep", frame: CGRect(x: 0, y: 0, width: 400, height: 200),
                                                accepts: [.item]) {
        received = $0
        return true
    })
    #expect(router.performDrop(second, in: view))
    for _ in 0..<500 where received == nil { try await Task.sleep(for: .milliseconds(10)) }
    let payload = try #require(received)
    #expect(payload.fileURLs.map(\.lastPathComponent) == ["cranny-test-photo.png"] && payload.contentTypes == [.png])
}

// MARK: - Swipe settings by observation

/// A pull down on the closed notch follows the fingers only while Gestures ▸ swipe to open is on, and the router
/// learns of the change without reading the settings with every sample.
@Test func theSwipeSettingsFollowTheSettingsStore() async throws {
    let registry = ModuleRegistry(services: .preview())
    let scene = NotchSceneModel(layout: NotchLayout(metrics: .reference), theme: CrannyTheme())
    let viewModel = NotchViewModel(scene: scene, registry: registry)
    viewModel.refresh()
    let router = GestureRouter(scene: scene, viewModel: viewModel, registry: registry)
    let canvas = CGRect(origin: .zero, size: scene.layout.canvasSize)
    var time: TimeInterval = 0
    /// A slow 10-pt pull, let go below the threshold: how far the shape followed.
    func pull() -> CGFloat {
        func sample(_ phase: SwipePhase, _ dy: CGFloat) -> ScrollSample {
            time += 1
            return ScrollSample(phase: phase, isMomentum: false, deltaX: 0, deltaY: dy, isPrecise: true,
                                isInvertedFromDevice: true, timestamp: time)
        }
        let point = CGPoint(x: canvas.midX, y: 10)
        _ = router.handle(sample(.began, 0), at: point, canvas: canvas)
        _ = router.handle(sample(.changed, 10), at: point, canvas: canvas)
        let followed = scene.gestureTranslation.height
        _ = router.handle(sample(.cancelled, 0), at: point, canvas: canvas)
        return followed
    }
    #expect(pull() > 0)
    #expect(scene.phase != .open && scene.gestureTranslation == .zero)

    registry.services.settings[CoreSettings.swipeOpenClose] = false
    var followed = pull()
    for _ in 0..<500 where followed > 0 {
        try await Task.sleep(for: .milliseconds(10))                            // the observation's hop
        followed = pull()
    }
    #expect(followed == 0)

    registry.services.settings[CoreSettings.swipeOpenClose] = true
    followed = pull()
    for _ in 0..<500 where followed == 0 {
        try await Task.sleep(for: .milliseconds(10))
        followed = pull()
    }
    #expect(followed > 0)
}

// MARK: - On screen (opt-in)

nonisolated private let integration = ProcessInfo.processInfo.environment["CRANNY_INTEGRATION"] == "1"

/// A real panel's zones follow its machine (every sync drops the kept ones): open widens them to the exit zone,
/// hiding behind the lock removes them, and the display's frame they were built with is the display's.
@Test(.enabled(if: integration)) func aRealPanelsZonesFollowItsMachine() throws {
    _ = NSApplication.shared
    let screen = try #require(NSScreen.screens.first)
    let registry = ModuleRegistry(services: .preview())
    let controller = NotchPanelController(screen: screen, key: "selftest.zones", style: .floatingIsland, registry: registry)
    defer { controller.close() }
    let closed = try #require(controller.hoverZones)
    #expect(!closed.expanded && closed.screenFrame == screen.frame)
    #expect(controller.hoverZones == closed)                                    // kept between events
    controller.viewModel.send(.open(page: nil, focus: nil, reason: .programmatic))
    let open = try #require(controller.hoverZones)
    #expect(open.expanded && open.shape.height > closed.shape.height)
    controller.viewModel.setEnvironment(NotchEnvironment(isLocked: true))
    #expect(controller.hoverZones == nil)
    controller.viewModel.setEnvironment(NotchEnvironment())
    #expect(controller.hoverZones?.expanded == false)
    controller.update(screen: screen, style: .floatingIsland)
    #expect(controller.hoverZones?.screenFrame == screen.frame)
}
