// A swipe-down open carries the fingers' speed into the open spring (DESIGN.md §4.4, ARCHITECTURE.md §10.20 issue 9):
// `SwipeTracker` measures it, `GestureRouter` sends it with the swipe, the reducer puts it in the open state that
// CrannyNotchUI animates. No windows, no posted input.
import CoreGraphics
import CrannyCore
import CrannyNotchUI
import Foundation
import Testing
@testable import CrannyAppShell

private let compact: NotchMachineConfig = {
    var c = NotchMachineConfig()
    c.primary = "test.primary"
    return c
}()

private func reduce(_ input: NotchInput, from state: NotchMachineState = NotchMachineState(),
                    config: NotchMachineConfig = NotchMachineConfig()) -> NotchMachineState {
    NotchMachine.reduce(state, input, now: 1, config: config).0
}

@Test func aSwipeDownOpensWithTheFingersSpeed() {
    for config in [NotchMachineConfig(), compact] {
        let open = reduce(.swipe(.down, target: .shape, velocity: 640), config: config)
        #expect(open.openState?.reason == .swipe && open.openState?.gestureVelocity == 640)
    }
    // A finger that moved back a little at the commit carries nothing backwards.
    #expect(reduce(.swipe(.down, target: .shape, velocity: -80)).openState?.gestureVelocity == 0)
    // Every other open starts from rest.
    #expect(reduce(.click).openState?.gestureVelocity == 0)
    #expect(reduce(.hotKey).openState?.gestureVelocity == 0)
    #expect(reduce(.swipe(.down, target: .shape)).openState?.gestureVelocity == 0)
    // Re-opening an open panel moves no shape: nothing to carry.
    let open = reduce(.swipe(.down, target: .shape, velocity: 640))
    #expect(reduce(.open(page: .tray, focus: nil, reason: .programmatic), from: open).openState?.gestureVelocity == 0)
    // Swipes that do not open carry nothing anywhere.
    #expect(reduce(.swipe(.up, target: .header, velocity: -500), from: open).isClosed)
}

/// Fingers moving down on a trackpad with natural scrolling (the deltas follow the fingers): 10 pt every 16 ms.
private func downSwipe() -> [ScrollSample] {
    func sample(_ phase: SwipePhase, _ dy: CGFloat, _ t: TimeInterval) -> ScrollSample {
        ScrollSample(phase: phase, isMomentum: false, deltaX: 0, deltaY: dy, isPrecise: true, isInvertedFromDevice: true, timestamp: t)
    }
    return [sample(.began, 0, 0)] + (1...6).map { sample(.changed, 10, Double($0) * 0.016) } + [sample(.ended, 0, 0.12)]
}

@MainActor @Test func theRouterHandsTheSwipesVelocityToTheOpen() throws {
    let registry = ModuleRegistry(services: .preview())
    let scene = NotchSceneModel(layout: NotchLayout(metrics: .reference), theme: CrannyTheme())
    let viewModel = NotchViewModel(scene: scene, registry: registry)
    viewModel.refresh()
    let router = GestureRouter(scene: scene, viewModel: viewModel, registry: registry)
    let canvas = CGRect(origin: .zero, size: scene.layout.canvasSize)
    for sample in downSwipe() { _ = router.handle(sample, at: CGPoint(x: canvas.midX, y: 10), canvas: canvas) }
    let open = try #require(scene.open)
    #expect(open.reason == .swipe && scene.phase == .open)
    #expect(abs(open.gestureVelocity - 625) < 1)                               // 10 pt per 16 ms at the commit
    #expect(scene.gestureTranslation == .zero)                                  // the rubber band let go
}
