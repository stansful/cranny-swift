import AppKit
import CrannyCore
import Foundation
import SwiftUI
import Testing
@testable import CrannyTimer

/// The face's ±1 min scroll zone, hosted in a window that is never shown (no input is posted: samples go straight to
/// the zones, as the shell's `NotchPanel.sendEvent` does).
@MainActor @Suite struct TimerScrollZoneTests {
    let zones = NotchZones()
    let h = TimerHarness()
    let center = CGPoint(x: 60, y: 60)

    @Test func scrollingAdjustsOnlyWhileTheFaceTakesInput() async throws {
        h.model.start(seconds: 600)
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 120, height: 120), styleMask: .borderless,
                              backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        let host = NSHostingView(rootView: face(editing: false))
        window.contentView = host
        await settle(host)

        #expect(scroll(fingersUp: 30))                                          // 30 pt up = 2 detents = +2 min
        #expect(h.model.state.remaining(at: h.clock.now) == 720)

        host.rootView = face(editing: true)                                     // edit mode: the zone goes away
        await settle(host)
        #expect(!scroll(fingersUp: 30))
        #expect(h.model.state.remaining(at: h.clock.now) == 720)

        host.rootView = face(editing: false)                                    // and comes back after it
        await settle(host)
        #expect(scroll(fingersUp: 15))
        #expect(h.model.state.remaining(at: h.clock.now) == 780)
        window.close()
    }

    private func face(editing: Bool) -> AnyView {
        AnyView(
            TimerFace(model: h.model,
                      context: WidgetContext(cells: 2, contentSize: CGSize(width: 96, height: 96), isEditingLayout: editing),
                      playHaptic: { _ in })
                .frame(width: 120, height: 120)
                .coordinateSpace(.named(NotchCoordinateSpace.name))
                .environment(\.notchZones, zones)
                .crannyThemeRoot(CrannyTheme()))
    }

    /// One touch sequence over the face; returns whether a zone took it.
    private func scroll(fingersUp distance: CGFloat) -> Bool {
        func sample(_ phase: SwipePhase, _ deltaY: CGFloat, _ t: TimeInterval) -> ScrollSample {
            ScrollSample(phase: phase, isMomentum: false, deltaX: 0, deltaY: deltaY, isPrecise: true,
                         isInvertedFromDevice: true, timestamp: t)
        }
        let began = zones.scroll(sample(.began, 0, 0), at: center)
        _ = zones.scroll(sample(.changed, -distance, 0.1), at: center)
        _ = zones.scroll(sample(.ended, 0, 0.2), at: center)
        return began
    }

    private func settle(_ host: NSView) async {
        host.layoutSubtreeIfNeeded()
        for _ in 0..<5 {
            try? await Task.sleep(for: .milliseconds(20))
            host.layoutSubtreeIfNeeded()
        }
    }
}
