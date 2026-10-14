// CrannyOnboarding/Stage/ScrollCatcher.swift — hands two-finger scrolls over the stage to the gesture practice
// (step 3). An AppKit view, because SwiftUI does not expose scroll phases and precise deltas on macOS 14. It
// takes part in hit-testing only for scroll events, so clicks still reach whatever is under it.
import AppKit
import CrannyCore
import SwiftUI

struct ScrollCatcher: NSViewRepresentable {
    let onScroll: @MainActor (ScrollSample) -> Void

    func makeNSView(context: Context) -> CatcherView {
        let view = CatcherView()
        view.onScroll = onScroll
        return view
    }

    func updateNSView(_ view: CatcherView, context: Context) {
        view.onScroll = onScroll
    }

    final class CatcherView: NSView {
        var onScroll: @MainActor (ScrollSample) -> Void = { _ in }

        override func hitTest(_ point: NSPoint) -> NSView? {
            NSApp.currentEvent?.type == .scrollWheel ? super.hitTest(point) : nil
        }

        override func scrollWheel(with event: NSEvent) {
            onScroll(Self.sample(event))
        }

        /// NSEvent → Core's AppKit-free sample (the same mapping the panel uses for `SwipeTracker`).
        static func sample(_ event: NSEvent) -> ScrollSample {
            ScrollSample(phase: phase(event.phase), isMomentum: !event.momentumPhase.isEmpty,
                         deltaX: event.scrollingDeltaX, deltaY: event.scrollingDeltaY,
                         isPrecise: event.hasPreciseScrollingDeltas,
                         isInvertedFromDevice: event.isDirectionInvertedFromDevice, timestamp: event.timestamp)
        }

        private static func phase(_ phase: NSEvent.Phase) -> SwipePhase {
            var result: SwipePhase = []
            if phase.contains(.began) { result.insert(.began) }
            if phase.contains(.stationary) { result.insert(.stationary) }
            if phase.contains(.changed) { result.insert(.changed) }
            if phase.contains(.ended) { result.insert(.ended) }
            if phase.contains(.cancelled) { result.insert(.cancelled) }
            if phase.contains(.mayBegin) { result.insert(.mayBegin) }
            return result
        }
    }
}
