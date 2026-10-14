// The key panel checks of R1 (docs/research/R1-notch-window.md §3–§4) re-run on the shipped panel
// (ARCHITECTURE.md §10.1 WP0 acceptance). Like R1's `--selftest`, they post NO input: in-process checks plus
// window-server queries (`CGWindowListCopyWindowInfo`, `NSWindow.windowNumber(at:belowWindowWithWindowNumber:)`,
// documented as "the window that would be hit by a mouse-down").
//
// - Configuration and root-view hit testing run everywhere (CI included).
// - The on-screen checks put a real panel at the top of the primary display for about two seconds, so they are
//   opt-in: `CRANNY_INTEGRATION=1 swift test --filter PanelSelfTests` (ARCHITECTURE.md §9.6).
// - `keyboardFocusIsTakenAndHandedBack` (also opt-in) checks that the hot key's programmatic `makeKey()` gives the
//   non-activating panel key status without activating Cranny or changing the frontmost app, and that closing
//   hands it back (ARCHITECTURE.md §4.10 [UNVERIFIED before WP13]). It briefly takes the keyboard: run it on an idle
//   Mac. It skips itself while the login window is in front (locked screen, screen saver), where nothing can become
//   key — the state WP13's machine was in, so it stays on the §11.2 hardware checklist.
// - Two more opt-in checks drive real controllers without input: a layout change that arrives during a peek is
//   applied once the peek ends (peeks never emit `.closed`), and a drop on one panel ends the drag on the others.
// - Not covered without real input (manual, §11.2 hardware checklist): a real click is delivered without
//   activating the app, and the panel shows above another app's full-screen Space.
import AppKit
import CoreGraphics
import CrannyCore
import CrannyNotchUI
import Foundation
import SwiftUI
import Testing
import UniformTypeIdentifiers
@testable import CrannyAppShell

// MARK: - Configuration (R1 §3.1)

@Test func panelIsConfiguredLikeR1() {
    let panel = NotchPanel(frame: CGRect(x: 0, y: 0, width: 400, height: 200))
    defer { panel.close() }
    #expect(panel.styleMask.contains(.nonactivatingPanel) && panel.styleMask.contains(.borderless))
    #expect(panel.level.rawValue == 26)                                        // statusBar + 1, set after isFloatingPanel
    #expect(panel.collectionBehavior.isSuperset(of: [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]))
    #expect(!panel.hidesOnDeactivate && panel.becomesKeyOnlyIfNeeded)
    #expect(panel.canBecomeKey && !panel.canBecomeMain)
    #expect(!panel.isOpaque && !panel.hasShadow && panel.backgroundColor == .clear)
}

/// AppKit only routes events inside the shape to SwiftUI (R1 §4.1); the window server's per-pixel pass-through
/// does the rest (checked on screen below).
@Test func rootViewHitTestsOnlyTheShape() {
    let root = NotchRootView(frame: CGRect(x: 0, y: 0, width: 400, height: 200))
    root.addSubview(NSView(frame: root.bounds))
    root.interactiveRect = { CGRect(x: 100, y: 150, width: 200, height: 50) }    // bottom-left coordinates
    #expect(root.hitTest(CGPoint(x: 200, y: 175)) != nil)
    #expect(root.hitTest(CGPoint(x: 20, y: 20)) == nil)
    #expect(root.hitTest(CGPoint(x: 200, y: 120)) == nil)                      // below the shape
    #expect(root.acceptsFirstMouse(for: nil))
    #expect(NotchHostingView(rootView: EmptyViewForTest()).acceptsFirstMouse(for: nil))  // R1 gotcha 6
}

private struct EmptyViewForTest: View { var body: some View { Color.clear } }

/// AppKit owns drag and drop (§5.6): the root view takes file URLs and file promises, and drops are refused
/// until a `DropRouter` is attached.
@Test func rootViewIsThePanelsDropDestination() {
    let root = NotchRootView(frame: CGRect(x: 0, y: 0, width: 400, height: 200))
    #expect(root.registeredDraggedTypes.contains(.fileURL))
    #expect(NSFilePromiseReceiver.readableDraggedTypes.allSatisfy { root.registeredDraggedTypes.contains(NSPasteboard.PasteboardType($0)) })
    #expect(!root.wantsPeriodicDraggingUpdates())
    #expect(DropRouter.canvasPoint(CGPoint(x: 10, y: 150), in: root) == CGPoint(x: 10, y: 50))   // top-left canvas
}

// MARK: - Esc ownership (§4.10)

/// A view that binds Esc the way NotchUI's keyboard map does (`.keyboardShortcut(.cancelAction)`).
private struct CancelButtonForTest: View {
    let onEscape: () -> Void
    var body: some View { Button("Back", action: onEscape).keyboardShortcut(.cancelAction) }
}

private func escapeEvent(in window: NSWindow) -> NSEvent? {
    NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                     context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53)
}

/// NotchUI owns the Esc chain; the shell's monitor offers each press to the panel's views first and runs the
/// machine's chain only when nothing took it: one press, one handler, whichever side binds Esc. Nothing is posted
/// to the system: the event object goes straight to the router, on a panel that is never ordered in.
@Test func escapeIsHandledOnceWhoeverOwnsIt() throws {
    _ = NSApplication.shared
    let registry = ModuleRegistry(services: .preview())
    let scene = NotchSceneModel(layout: NotchLayout(metrics: .reference), theme: CrannyTheme())
    let viewModel = NotchViewModel(scene: scene, registry: registry)
    let panel = NotchPanel(frame: CGRect(x: 0, y: 0, width: 400, height: 200))
    defer { panel.close() }
    let router = KeyboardRouter(panel: panel, viewModel: viewModel, registry: registry)

    // Nothing in the panel binds Esc: the shell's chain closes, and the press is consumed.
    panel.contentView = NSView(frame: panel.frame)
    viewModel.send(.open(page: nil, focus: nil, reason: .programmatic))
    let bare = try #require(escapeEvent(in: panel))
    #expect(router.handleKeyDown(bare) == nil && viewModel.state.isClosed)

    // NotchUI binds Esc: its binding takes the press (as a key equivalent), and the shell's chain does not run.
    var notchUIHandled = 0
    let host = NSHostingView(rootView: CancelButtonForTest { notchUIHandled += 1 })
    host.frame = CGRect(x: 0, y: 0, width: 400, height: 200)
    panel.contentView = host
    host.layoutSubtreeIfNeeded()
    viewModel.send(.open(page: nil, focus: nil, reason: .programmatic))
    let bound = try #require(escapeEvent(in: panel))
    #expect(router.handleKeyDown(bound) == nil)
    #expect(notchUIHandled == 1 && viewModel.state.isOpen, "NotchUI: \(notchUIHandled), shell closed: \(viewModel.state.isClosed)")
}

// MARK: - On screen (opt-in)

nonisolated private let integration = ProcessInfo.processInfo.environment["CRANNY_INTEGRATION"] == "1"

private func spin(_ seconds: Double) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }

/// The window server's hit region follows what was drawn after the next composite, which can lag a morph by
/// a second or two (much longer while the screen is locked): wait for it instead of sleeping a fixed time.
private func eventually(within seconds: Double = 6, _ condition: () -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline {
        if condition() { return true }
        spin(0.1)
    }
    return condition()
}

/// The panel's window-server entry and the number of the window directly in front of it (0 = none), so a
/// hit query can start at our panel whatever covers it (menus, a lock screen).
private func windowServerEntry(of number: Int) -> (layer: Int, bounds: CGRect, above: Int)? {
    let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
    guard let index = list.firstIndex(where: { $0[kCGWindowNumber as String] as? Int == number }) else { return nil }
    let entry = list[index]
    let bounds = (entry[kCGWindowBounds as String] as? NSDictionary).flatMap { CGRect(dictionaryRepresentation: $0 as CFDictionary) } ?? .zero
    let above = index > 0 ? list[index - 1][kCGWindowNumber as String] as? Int ?? 0 : 0
    return (entry[kCGWindowLayer as String] as? Int ?? -1, bounds, above)
}

private extension NSScreen {
    var hasNotchForSelfTest: Bool { safeAreaInsets.top > 0 }
}

@Test(.enabled(if: integration)) func panelOnScreenMatchesR1() throws {
    _ = NSApplication.shared
    let screen = try #require(NSScreen.screens.first)
    let frontBefore = NSWorkspace.shared.frontmostApplication?.processIdentifier
    let registry = ModuleRegistry(services: .preview())
    let controller = NotchPanelController(screen: screen, key: "selftest", style: .floatingIsland, registry: registry)
    defer { controller.close() }
    spin(0.8)                                                                   // SwiftUI draws, the window server composites

    // Ordering front never activates the app or changes the frontmost app (R1 §3.1, §3.5).
    #expect(!NSRunningApplication.current.isActive)
    #expect(NSWorkspace.shared.frontmostApplication?.processIdentifier == frontBefore)

    // Level 26 and exactly the requested frame in the window server (R1 §3.2).
    let panel = controller.panel
    let entry = try #require(windowServerEntry(of: panel.windowNumber))
    #expect(entry.layer == 26)
    let primaryHeight = NSScreen.screens[0].frame.maxY
    #expect(entry.bounds == CGRect(x: panel.frame.minX, y: primaryHeight - panel.frame.maxY,
                                   width: panel.frame.width, height: panel.frame.height))

    // Per-pixel pass-through (R1 §4.1): the drawn shape takes the click, the transparent canvas does not.
    func hits(_ point: CGPoint) -> Bool {
        NSWindow.windowNumber(at: point, belowWindowWithWindowNumber: windowServerEntry(of: panel.windowNumber)?.above ?? 0)
            == panel.windowNumber
    }
    let closed = controller.shapeFrameOnScreen
    #expect(eventually { hits(CGPoint(x: closed.midX, y: closed.midY)) })
    #expect(!hits(CGPoint(x: panel.frame.minX + 4, y: panel.frame.minY + 4)))   // empty canvas corner
    #expect(!hits(CGPoint(x: closed.midX, y: closed.minY - 12)))                 // under the closed shape
    if !screen.hasNotchForSelfTest {                                             // "Hidden until hover": alpha 0 passes through
        registry.services.settings[CoreSettings.handleVisibility] = .hiddenUntilHover
        #expect(eventually { !hits(CGPoint(x: closed.midX, y: closed.midY)) })
        registry.services.settings[CoreSettings.handleVisibility] = .visible
        #expect(eventually { hits(CGPoint(x: closed.midX, y: closed.midY)) })
    }

    controller.viewModel.send(.open(page: nil, focus: nil, reason: .programmatic))
    controller.viewModel.send(.hold("selftest", true))
    spin(1.0)                                                                   // the open spring settles
    let open = controller.shapeFrameOnScreen
    #expect(open.height > closed.height)
    #expect(eventually { hits(CGPoint(x: open.midX, y: open.minY + open.height * 0.3)) })   // inside the open panel
    #expect(!hits(CGPoint(x: open.minX + 2, y: open.minY + 2)))                // outside the rounded bottom corner
    #expect(!hits(CGPoint(x: open.midX, y: open.minY - 6)))                    // the shadow does not capture
    #expect(NSWorkspace.shared.frontmostApplication?.processIdentifier == frontBefore)
}

/// While the login window is in front (locked screen, screen saver) no window of any app can become key.
nonisolated private func sessionIsUnlocked() -> Bool {
    NSWorkspace.shared.frontmostApplication?.bundleIdentifier != "com.apple.loginwindow"
}

@Test(.enabled(if: integration), .enabled(if: sessionIsUnlocked(), "needs an unlocked session"))
func keyboardFocusIsTakenAndHandedBack() throws {
    _ = NSApplication.shared
    // The test runner is an unbundled process (activation policy `.prohibited`: no key windows at all);
    // Cranny is an agent app (`LSUIElement`), so run as one.
    NSApp.setActivationPolicy(.accessory)
    NSApp.finishLaunching()                                                     // connect like a launched app
    let screen = try #require(NSScreen.screens.first)
    let frontBefore = NSWorkspace.shared.frontmostApplication?.processIdentifier
    let registry = ModuleRegistry(services: .preview())
    let controller = NotchPanelController(screen: screen, key: "selftest.keys", style: .floatingIsland, registry: registry)
    defer { controller.close() }
    spin(0.5)
    controller.viewModel.send(.hotKey)                                          // opens with `makeKey`
    #expect(eventually(within: 3) { controller.panel.isKeyWindow })
    #expect(controller.viewModel.state.holds.contains(NotchMachineState.typingHold))   // key status is a hold (§4.5)
    #expect(NSWorkspace.shared.frontmostApplication?.processIdentifier == frontBefore)  // no activation (R1 §3.5)
    controller.viewModel.send(.escape)                                          // closes and hands focus back
    #expect(eventually(within: 3) { !controller.panel.isKeyWindow })
    #expect(!controller.viewModel.state.holds.contains(NotchMachineState.typingHold))
    #expect(controller.panel.isVisible)                                         // orderOut + orderFrontRegardless
    #expect(NSWorkspace.shared.frontmostApplication?.processIdentifier == frontBefore)
}

/// A canvas change (density here; display reconfiguration and Notch fit take the same path) must not resize the
/// panel mid-morph, and must not be lost when the surface returns to closed without a `.closed` event (a peek).
@Test(.enabled(if: integration)) func aLayoutChangeDuringAPeekIsAppliedAfterIt() throws {
    _ = NSApplication.shared
    let screen = try #require(NSScreen.screens.first)
    let registry = ModuleRegistry(services: .preview())
    let controller = NotchPanelController(screen: screen, key: "selftest.layout", style: .floatingIsland, registry: registry)
    defer { controller.close() }
    spin(0.3)
    controller.viewModel.send(.autoPeek(.flash, until: .infinity))
    let before = controller.scene.layout, frameBefore = controller.panel.frame
    registry.services.settings[CoreSettings.density] = .roomy
    spin(0.3)                                                                   // the observation hop
    #expect(controller.scene.layout == before && controller.panel.frame == frameBefore)   // not during the peek
    controller.viewModel.send(.close)                                           // the peek ends: no `.closed` event
    #expect(eventually(within: 3) { controller.scene.layout != before })
    #expect(controller.scene.layout.grid.density == .roomy)
    #expect(controller.panel.frame == NotchPanelController.panelFrame(canvas: controller.scene.layout.canvasSize, screen: screen))
}

/// A drop on one panel ends the drag everywhere: another panel the drag passed lets go of its `drag` hold and its
/// enlarged drop zone (which would otherwise capture menu-bar clicks around its notch).
@Test(.enabled(if: integration)) func aDropOnOnePanelEndsTheDragOnTheOthers() throws {
    _ = NSApplication.shared
    let screen = try #require(NSScreen.screens.first)
    let registry = ModuleRegistry(services: .preview())
    let overlay = OverlayCoordinator(registry: registry, environment: ShellEnvironment())
    let dropping = NotchPanelController(screen: screen, key: "selftest.a", style: .floatingIsland, registry: registry)
    let passed = NotchPanelController(screen: screen, key: "selftest.b", style: .floatingIsland, registry: registry)
    defer { dropping.close(); passed.close() }
    overlay.controllers = ["selftest.a": dropping, "selftest.b": passed]
    passed.viewModel.send(.open(page: nil, focus: nil, reason: .programmatic))
    passed.viewModel.send(.fileDragEntered([.pdf]))
    #expect(passed.chrome.dropZone != nil && passed.viewModel.state.holds.contains(NotchMachineState.dragHold))
    dropping.viewModel.send(.filesDropped(count: 1))
    overlay.dropFinished(on: dropping)
    #expect(passed.viewModel.state.fileDrag == nil && passed.viewModel.state.holds.isEmpty)
    #expect(passed.chrome.dropZone == nil)
}
