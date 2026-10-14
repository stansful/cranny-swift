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
// - Not covered without real input (manual, §11.2 hardware checklist): a real click is delivered without
//   activating the app, and the panel shows above another app's full-screen Space.
import AppKit
import CoreGraphics
import CrannyCore
import CrannyNotchUI
import Foundation
import SwiftUI
import Testing
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
