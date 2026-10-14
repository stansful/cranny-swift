// Input policies of the shell: two-finger swipes reach activities as physical finger directions (DESIGN.md §4.4),
// and an open nobody is looking at closes after a glance (ARCHITECTURE.md §4.4). No windows, no posted input.
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

// MARK: - Unattended opens (C-SHELL-9)

private func reduce(_ s: NotchMachineState, _ input: NotchInput, config: NotchMachineConfig = NotchMachineConfig())
    -> (NotchMachineState, [NotchEffect]) {
    NotchMachine.reduce(s, input, now: 100, config: config)
}

/// Welcome's Done, the Tray opening after a slow drop: opened by code with the pointer elsewhere, the panel stays for
/// a glance and then closes like one the pointer left; the pointer coming in keeps it.
@Test func anOpenNobodyLooksAtClosesAfterAGlance() {
    for reason in [OpenReason.programmatic, .drag, .activity] {
        var (s, fx) = reduce(NotchMachineState(), .open(page: .tray, focus: nil, reason: reason))
        #expect(s.isOpen && fx.contains(.schedule(.grace, after: NotchMachine.unattendedOpenGrace)), "\(reason)")
        (s, _) = reduce(s, .timerElapsed(.grace))
        #expect(s.isClosed, "\(reason)")
    }
    var (s, _) = reduce(NotchMachineState(), .open(page: nil, focus: nil, reason: .programmatic))
    (s, _) = reduce(s, .pointerEntered)                                         // the user came to look
    #expect(!s.timers.contains(.grace))
    (s, _) = reduce(s, .timerElapsed(.grace))
    #expect(s.isOpen)
}

/// Keyboard opens are key (they close when they resign), clicks were made by the pointer or VoiceOver, and VoiceOver
/// users navigate without the pointer; pinned, held or "Close when the pointer leaves" off: it stays.
@Test func anOpenThatSomeoneUsesHasNoGlanceTimer() {
    func armsGrace(_ input: NotchInput, _ state: NotchMachineState = NotchMachineState(),
                   config: NotchMachineConfig = NotchMachineConfig()) -> Bool {
        reduce(state, input, config: config).0.timers.contains(.grace)
    }
    #expect(!armsGrace(.hotKey))
    #expect(!armsGrace(.open(page: nil, focus: nil, reason: .keyboard)))
    #expect(!armsGrace(.open(page: nil, focus: nil, reason: .click)))
    var voiceOver = NotchMachineConfig()
    voiceOver.voiceOverRunning = true
    #expect(!armsGrace(.open(page: nil, focus: nil, reason: .programmatic), config: voiceOver))
    var stays = NotchMachineConfig()
    stays.closeOnLeave = false
    #expect(!armsGrace(.open(page: nil, focus: nil, reason: .programmatic), config: stays))
    var pinned = NotchMachineState()
    pinned.pinned = true
    #expect(!armsGrace(.open(page: nil, focus: nil, reason: .programmatic), pinned))
    var held = NotchMachineState()
    held.holds = ["preview"]
    #expect(!armsGrace(.open(page: nil, focus: nil, reason: .programmatic), held))
    var inside = NotchMachineState()
    inside.hover = .inside
    #expect(!armsGrace(.open(page: nil, focus: nil, reason: .programmatic), inside))
    var tray = NotchMachineConfig()
    tray.acceptsFileDrags = true
    let catching = reduce(NotchMachineState(), .fileDragEntered([.pdf]), config: tray).0
    #expect(catching.isCatching && !catching.timers.contains(.grace))           // the catch state has its own return
}

