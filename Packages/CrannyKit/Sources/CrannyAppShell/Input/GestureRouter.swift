// CrannyAppShell/Input/GestureRouter.swift — two-finger swipes over one panel (ARCHITECTURE.md §5.6, DESIGN.md §4.4).
// Every scroll event reaches `NotchPanel.sendEvent` first, even while the panel is not key (R1 §6). Closed, compact
// and peek: the shell's own `SwipeTracker(axis: .any)` drives open (down), dismiss (up; over the satellite it
// dismisses the satellite) and track swipes (left/right), with live rubber-banding in `scene.gestureTranslation`.
// Open: a scroll zone under the pointer takes the event; else a vertical swipe up over the header row closes;
// else SwiftUI gets it (`ScrollView`s in widgets). Phase-less wheel events never form gestures.
import AppKit
import CrannyCore
import CrannyNotchUI
import Foundation

@MainActor final class GestureRouter {
    private let scene: NotchSceneModel
    private let viewModel: NotchViewModel
    private let registry: ModuleRegistry
    private var tracker = SwipeTracker(axis: .any)
    private var target: SwipeTarget = .shape
    private var headerTracker = SwipeTracker(axis: .vertical)
    private var overHeader = false

    init(scene: NotchSceneModel, viewModel: NotchViewModel, registry: ModuleRegistry) {
        self.scene = scene; self.viewModel = viewModel; self.registry = registry
    }

    /// `NotchPanel.scrollInterceptor`: true = consumed.
    func handle(_ event: NSEvent, in view: NSView) -> Bool {
        let sample = Self.sample(event)
        let local = view.convert(event.locationInWindow, from: nil)
        let point = CGPoint(x: local.x, y: view.bounds.height - local.y)          // canvas: top-left origin
        switch scene.phase {
        case .hidden:
            return false
        case .open:
            if scene.zones.scroll(sample, at: point) { return true }
            return headerSwipe(sample, at: point)
        case .idle, .breath, .compact, .peek:
            guard sample.isPrecise, !sample.phase.isEmpty else { return false }   // a mouse wheel is not a swipe
            return shapeSwipe(sample, at: point, canvas: view.bounds)
        }
    }

    // MARK: Closed, compact, peek

    private func shapeSwipe(_ sample: ScrollSample, at point: CGPoint, canvas: CGRect) -> Bool {
        if sample.phase.contains(.began) || sample.phase.contains(.mayBegin) {
            target = satelliteFrame(in: canvas)?.insetBy(dx: -4, dy: -4).contains(point) == true ? .satellite : .shape
        }
        let settings = registry.services.settings
        tracker.sensitivity = CGFloat(settings[CoreSettings.gestureSensitivity])
        tracker.invertHorizontal = settings[CoreSettings.invertTrackSwipe]
        switch tracker.handle(sample) {
        case .tracking(let axis, let translation)?:
            viewModel.setGestureTranslation(rubberBand(axis, translation))
        case .committed(let direction, _)?:
            viewModel.setGestureTranslation(.zero)
            viewModel.send(.swipe(direction, target: target))
        case .cancelled?:
            viewModel.setGestureTranslation(.zero)
        case nil:
            break
        }
        return true                                                              // nothing else scrolls while closed
    }

    /// Live feedback only for gestures that can commit here (DESIGN.md §4.4 "Live feedback").
    private func rubberBand(_ axis: SwipeAxis, _ translation: CGFloat) -> CGSize {
        let settings = registry.services.settings
        let lineup = viewModel.lineup
        switch axis {
        case .horizontal:
            guard settings[CoreSettings.trackSwipe], lineup.primary != nil, target == .shape else { return .zero }
            return CGSize(width: CrannyMotion.rubberBand(translation, limit: GestureSpec.horizontalTravel), height: 0)
        case .vertical:
            let down = translation > 0
            guard down ? settings[CoreSettings.swipeOpenClose] : settings[CoreSettings.swipeToDismiss] || lineup.primary == nil
            else { return .zero }
            return CGSize(width: 0, height: CrannyMotion.rubberBand(translation, limit: GestureSpec.verticalTravel))
        case .any:
            return .zero
        }
    }

    /// The satellite bubble in canvas coordinates, while compact shows one.
    private func satelliteFrame(in canvas: CGRect) -> CGRect? {
        guard scene.phase == .compact, scene.satellite != nil else { return nil }
        return scene.layout.satelliteFrame(beside: scene.layout.compact(scene.primarySlot), in: canvas)
    }

    // MARK: Open: swipe up over the header row closes

    private func headerSwipe(_ sample: ScrollSample, at point: CGPoint) -> Bool {
        guard sample.isPrecise, !sample.phase.isEmpty else { return false }
        if sample.phase.contains(.began) || sample.phase.contains(.mayBegin) {
            // Scrolls reach the panel only over drawn pixels, so the shape bounds the row horizontally.
            let top = scene.geometry.topInset
            overHeader = point.y >= top && point.y <= top + scene.layout.headerHeight
        }
        guard overHeader, registry.services.settings[CoreSettings.swipeOpenClose] else { return false }
        headerTracker.sensitivity = CGFloat(registry.services.settings[CoreSettings.gestureSensitivity])
        let update = headerTracker.handle(sample)
        if sample.phase.contains(.ended) || sample.phase.contains(.cancelled) { overHeader = false }
        switch update {
        case .tracking(_, let translation)?:
            // The shape follows upward only (up to −20 pt); pulling down does nothing while open.
            viewModel.setGestureTranslation(CGSize(width: 0, height: CrannyMotion.rubberBand(min(translation, 0),
                                                                                                limit: GestureSpec.verticalTravel)))
            return true
        case .committed(let direction, _)?:
            viewModel.setGestureTranslation(.zero)
            if direction == .up { viewModel.send(.swipe(.up, target: .header)) }
            return true
        case .cancelled?:
            viewModel.setGestureTranslation(.zero)
            return true
        case nil:
            return false
        }
    }

    // MARK: Pure helpers (unit-tested)

    /// `NSEvent` → `ScrollSample` (Core mirrors the AppKit fields without importing AppKit).
    static func sample(_ event: NSEvent) -> ScrollSample {
        ScrollSample(phase: swipePhase(event.phase), isMomentum: !event.momentumPhase.isEmpty,
                     deltaX: event.scrollingDeltaX, deltaY: event.scrollingDeltaY,
                     isPrecise: event.hasPreciseScrollingDeltas, isInvertedFromDevice: event.isDirectionInvertedFromDevice,
                     timestamp: event.timestamp)
    }

    nonisolated static func swipePhase(_ phase: NSEvent.Phase) -> SwipePhase {
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
