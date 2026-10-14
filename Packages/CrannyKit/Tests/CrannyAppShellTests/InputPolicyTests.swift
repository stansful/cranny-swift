// Input policies of the shell: two-finger swipes reach activities as physical finger directions (DESIGN.md §4.4).
// No windows, no posted input.
import AppKit
import CrannyCore
import CrannyNotchUI
import Foundation
import Observation
import SwiftUI
import Testing
import UniformTypeIdentifiers
@testable import CrannyAppShell

@MainActor @Observable private final class SwipeProbe: LiveActivity {
    let id: ActivityID = "probe.swipe"
    var isActive = true
    var priority: ActivityPriority = .ongoing
    var slot: SlotWidth = .medium
    var revision = 1
    var accessibilityLabel: String { "Probe" }
    private(set) var gestures: [ActivityGesture] = []
    func handle(_ gesture: ActivityGesture) -> Bool { gestures.append(gesture); return true }
    func compactLeading() -> some View { EmptyView() }
    func compactTrailing() -> some View { EmptyView() }
    func minimal() -> some View { EmptyView() }
    func peekRow() -> some View { EmptyView() }
}

/// Fingers moving left on a trackpad with natural scrolling (the deltas follow the fingers).
private func leftSwipe() -> [ScrollSample] {
    func sample(_ phase: SwipePhase, _ dx: CGFloat, _ t: TimeInterval) -> ScrollSample {
        ScrollSample(phase: phase, isMomentum: false, deltaX: dx, deltaY: 0, isPrecise: true, isInvertedFromDevice: true, timestamp: t)
    }
    return [sample(.began, 0, 0)] + (1...8).map { sample(.changed, -10, Double($0) * 0.016) } + [sample(.ended, 0, 0.15)]
}

/// C-SHELL-4: Gestures ▸ Invert is applied once, by the activity (`TrackSwipe`), as the Media widget does: the shell
/// reports the physical direction whatever the setting, so Invert really flips compact and peek.
@Test(arguments: [false, true])
func swipesReachActivitiesAsPhysicalDirections(_ invert: Bool) {
    let registry = ModuleRegistry(services: .preview())
    let probe = SwipeProbe()
    registry.add(activity: probe, kind: ActivityKind(id: probe.id, module: "probe", title: "Probe", symbol: "music.note",
                                                     defaultPriority: .ongoing))
    registry.services.settings[CoreSettings.invertTrackSwipe] = invert
    let scene = NotchSceneModel(layout: NotchLayout(metrics: .reference), theme: CrannyTheme())
    let viewModel = NotchViewModel(scene: scene, registry: registry)
    viewModel.setLineup(Lineup(primary: probe.id, primarySlot: .medium))
    #expect(scene.phase == .compact)
    let router = GestureRouter(scene: scene, viewModel: viewModel, registry: registry)
    let canvas = CGRect(origin: .zero, size: scene.layout.canvasSize)
    for sample in leftSwipe() { _ = router.handle(sample, at: CGPoint(x: canvas.midX, y: 10), canvas: canvas) }
    #expect(probe.gestures == [.swipeLeft])
}

