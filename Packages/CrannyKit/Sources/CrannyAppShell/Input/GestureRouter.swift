// CrannyAppShell/Input/GestureRouter.swift — two-finger swipes over one panel (ARCHITECTURE.md §5.6, DESIGN.md §4.4).
// Every scroll event reaches `NotchPanel.sendEvent` first, even while the panel is not key (R1 §6). Closed, compact
// and peek: the shell's own `SwipeTracker(axis: .any)` drives open (down), dismiss (up; over the satellite it
// dismisses the satellite) and track swipes (left/right), with live rubber-banding in `scene.gestureTranslation`.
// Over a peek, the gesture acts on the row under the fingers (else on what the peek shows, §4.4). Horizontal swipes
// reach activities as physical finger directions; the activity applies Gestures ▸ Invert itself.
// Open: a scroll zone under the pointer takes the event; else a vertical swipe up over the header row closes;
// else SwiftUI gets it (`ScrollView`s in widgets). Phase-less wheel events never form gestures.
// The swipe settings (sensitivity and the three swipe toggles) are kept current by observation, not read from the
// settings store with every scroll sample.
import AppKit
import CrannyCore
import CrannyNotchUI
import Foundation

@MainActor final class GestureRouter {
    private let scene: NotchSceneModel
    private let viewModel: NotchViewModel
    private var tracker = SwipeTracker(axis: .any)
    private var target: SwipeTarget = .shape
    private var headerTracker = SwipeTracker(axis: .vertical)
    private var overHeader = false
    /// Gestures ▸ sensitivity and swipe toggles as they are now (`settingsToken` follows every change).
    private var swipeSettings: SwipeSettings
    /// Observes the swipe settings for as long as the router lives.
    private var settingsToken: ObservationToken?

    init(scene: NotchSceneModel, viewModel: NotchViewModel, registry: ModuleRegistry) {
        self.scene = scene; self.viewModel = viewModel
        let settings = registry.services.settings
        swipeSettings = SwipeSettings(settings)
        tracker.sensitivity = swipeSettings.sensitivity
        headerTracker.sensitivity = swipeSettings.sensitivity
        settingsToken = observe({ SwipeSettings(settings) }) { [weak self] in self?.settingsChanged($0) }
    }

    /// The settings a swipe reads.
    private struct SwipeSettings: Equatable {
        var sensitivity: CGFloat
        var trackSwipe: Bool
        var swipeOpenClose: Bool
        var swipeToDismiss: Bool

        init(_ settings: SettingsStore) {
            sensitivity = CGFloat(settings[CoreSettings.gestureSensitivity])
            trackSwipe = settings[CoreSettings.trackSwipe]
            swipeOpenClose = settings[CoreSettings.swipeOpenClose]
            swipeToDismiss = settings[CoreSettings.swipeToDismiss]
        }
    }

    private func settingsChanged(_ settings: SwipeSettings) {
        swipeSettings = settings
        tracker.sensitivity = settings.sensitivity
        headerTracker.sensitivity = settings.sensitivity
    }

    /// `NotchPanel.scrollInterceptor`: true = consumed.
    func handle(_ event: NSEvent, in view: NSView) -> Bool {
        let local = view.convert(event.locationInWindow, from: nil)
        let point = CGPoint(x: local.x, y: view.bounds.height - local.y)          // canvas: top-left origin
        return handle(Self.sample(event), at: point, canvas: view.bounds)
    }

    /// One scroll sample at `point` (canvas, top-left origin): true = consumed.
    func handle(_ sample: ScrollSample, at point: CGPoint, canvas: CGRect) -> Bool {
        switch scene.phase {
        case .hidden:
            return false
        case .open:
            if scene.zones.scroll(sample, at: point) { return true }
            return headerSwipe(sample, at: point)
        case .idle, .breath, .compact, .peek:
            guard sample.isPrecise, !sample.phase.isEmpty else { return false }   // a mouse wheel is not a swipe
            return shapeSwipe(sample, at: point, canvas: canvas)
        }
    }

    // MARK: Closed, compact, peek

    private func shapeSwipe(_ sample: ScrollSample, at point: CGPoint, canvas: CGRect) -> Bool {
        if sample.phase.contains(.began) || sample.phase.contains(.mayBegin) {
            if viewModel.satelliteFrame(in: canvas)?.insetBy(dx: -4, dy: -4).contains(point) == true {
                target = .satellite
            } else if scene.phase == .peek, let id = Self.peekRow(at: point, layout: scene.layout, geometry: scene.geometry,
                                                                   rows: scene.peekRows) {
                target = .row(id)                                                // the gesture acts on that row
            } else {
                target = .shape
            }
        }
        // Directions stay physical finger motion: Gestures ▸ Invert is applied once, by the activity that changes
        // the track (`TrackSwipe`), exactly as the Media widget's own scroll zones do. Inverting here as well would
        // cancel it out over compact and peek.
        switch tracker.handle(sample) {
        case .tracking(let axis, let translation)?:
            viewModel.setGestureTranslation(rubberBand(axis, translation))
        case .committed(let direction, let velocity)?:
            viewModel.setGestureTranslation(.zero)
            // The fingers' speed rides along: a swipe down opens with it (DESIGN.md §4.4).
            viewModel.send(.swipe(direction, target: target, velocity: velocity))
        case .cancelled?:
            viewModel.setGestureTranslation(.zero)
        case nil:
            break
        }
        return true                                                              // nothing else scrolls while closed
    }

    /// Live feedback only for gestures that can commit here (DESIGN.md §4.4 "Live feedback").
    private func rubberBand(_ axis: SwipeAxis, _ translation: CGFloat) -> CGSize {
        let settings = swipeSettings
        let lineup = viewModel.lineup
        switch axis {
        case .horizontal:
            guard settings.trackSwipe, target != .satellite, lineup.primary != nil || !scene.peekRows.isEmpty
            else { return .zero }
            return CGSize(width: CrannyMotion.rubberBand(translation, limit: GestureSpec.horizontalTravel), height: 0)
        case .vertical:
            let down = translation > 0
            guard down ? settings.swipeOpenClose : settings.swipeToDismiss || lineup.primary == nil
            else { return .zero }
            return CGSize(width: 0, height: CrannyMotion.rubberBand(translation, limit: GestureSpec.verticalTravel))
        case .any:
            return .zero
        }
    }

    /// The peek row under `point` (canvas, top-left origin): below the band row, one `NotchLayout.peekRow` per
    /// activity (DESIGN.md §9.3). Nil over the band row, the bottom inset or outside the rows.
    static func peekRow(at point: CGPoint, layout: NotchLayout, geometry: NotchGeometry, rows: [ActivityID]) -> ActivityID? {
        let top = geometry.topInset + layout.rowHeight
        guard point.y >= top else { return nil }
        let index = Int((point.y - top) / NotchLayout.peekRow)
        return rows.indices.contains(index) ? rows[index] : nil
    }

    // MARK: Open: swipe up over the header row closes

    private func headerSwipe(_ sample: ScrollSample, at point: CGPoint) -> Bool {
        guard sample.isPrecise, !sample.phase.isEmpty else { return false }
        if sample.phase.contains(.began) || sample.phase.contains(.mayBegin) {
            // Scrolls reach the panel only over drawn pixels, so the shape bounds the row horizontally.
            let top = scene.geometry.topInset
            overHeader = point.y >= top && point.y <= top + scene.layout.headerHeight
        }
        guard overHeader, swipeSettings.swipeOpenClose else { return false }
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
