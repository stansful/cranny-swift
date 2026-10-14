// CrannyAppShell/Overlay/OverlayCoordinator+Control.swift — what `ShellNotchControl` and `AppControl.showOnNotch`
// ask of the panels (ARCHITECTURE.md §3.9, §10.0): open/close/pin/holds/focus on the right display, peeks, key
// focus, calibration, the flash activity, "Show on Notch" with the modules' own sample activities, and visual QA.
import AppKit
import CrannyCore
import CrannyNotchUI
import Foundation
import os

private let log = Log.logger(.overlay)

extension OverlayCoordinator {
    // MARK: NotchControl

    func open(page: PageID?, focus: WidgetID?, reason: OpenReason) {
        refreshEnvironmentNow()
        let target = openController ?? alertController
        target?.viewModel.send(.open(page: page, focus: focus, reason: reason))
    }
    func closeAll() { for controller in controllers.values { controller.viewModel.send(.close) } }
    func togglePinned() { setPinned(!isPinned) }
    func setHoldOpen(_ hold: Bool, reason: String) {
        for controller in controllers.values { controller.viewModel.send(.hold(reason, hold)) }
    }
    func setFocusMode(_ widget: WidgetID?) {
        openController?.viewModel.send(.setMode(widget.map { .focus($0) } ?? .grid))
    }
    func requestKeyboardFocus() { openController?.viewModel.makeKey() }
    func requestPeek(_ activity: ActivityID) { requestAutoPeek(activity) }
    func shapeFrameOnScreen() -> CGRect? { (openController ?? alertController)?.shapeFrameOnScreen }

    /// Appearance ▸ Notch fit: every panel outlines its closed shape over its hardware.
    func setCalibrating(_ on: Bool) {
        isCalibrating = on
        for controller in controllers.values { controller.setCalibrating(on) }
    }

    // MARK: Flash (`NotchControl.flash`, §10.0)

    /// A transient P1 compact activity on ONE display — `display`, else the pointer's. Dropped while Live Activities
    /// are paused, the screen is locked or asleep, or that display's panel is hidden. `duration` > 2.6 s only for
    /// "Show on Notch" and visual QA.
    func showFlash(symbol: String, label: String, duration: TimeInterval, on display: DisplayKey? = nil) {
        guard !environment.areLiveActivitiesPaused, !environment.isScreenLocked, !environment.areDisplaysAsleep else { return }
        presentFlash(symbol: symbol, label: label, duration: duration, on: display)
    }

    /// Puts the flash on one display without the pause/lock policy (visual QA forces states on any screen).
    func presentFlash(symbol: String, label: String, duration: TimeInterval, on display: DisplayKey?) {
        guard let target = display.flatMap({ controllers[$0] }) ?? alertController, !target.viewModel.state.blocksInput else { return }
        flashDisplay = target.key
        notchControl.flashActivity.show(symbol: symbol, label: label, duration: duration)
    }

    // MARK: Show on Notch (`AppControl.showOnNotch`)

    /// Plays a Settings preview state on the real notch for `duration`, with the modules' sample activities
    /// (`RegisteredActivity.makeSample`) so the user sees the real views; nothing touches the modules' models.
    func play(_ state: PreviewStageState, for duration: Duration) {
        guard let controller = alertController else { return }
        endPreview()
        let viewModel = controller.viewModel
        switch state {
        case .closed:
            viewModel.send(.close)
        case .open:
            viewModel.send(.open(page: nil, focus: nil, reason: .programmatic))
        case .activity, .peek, .hud:
            if let (id, sample) = sampleActivity(for: state) {
                controller.scene.sampleActivities[id] = sample
                viewModel.overrideLineup(Lineup(primary: id, primarySlot: sample.slot))
                preview = (controller.key, id)
                if state == .peek { viewModel.send(.autoPeek(id, until: .infinity)) }
            } else {
                showFlash(symbol: "sparkles", label: "Cranny", duration: duration.seconds, on: controller.key)
            }
        }
        viewModel.send(.hold(Self.previewHold, true))
        playTask = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled, let self else { return }
            self.endPreview()
        }
    }

    static let previewHold = "preview"

    private func endPreview() {
        playTask?.cancel()
        playTask = nil
        for controller in controllers.values where controller.viewModel.state.holds.contains(Self.previewHold) {
            controller.viewModel.send(.hold(Self.previewHold, false))
            controller.viewModel.send(.close)
        }
        guard let preview else { return }
        self.preview = nil
        if let controller = controllers[preview.key] {
            controller.viewModel.overrideLineup(nil)
            controller.scene.sampleActivities[preview.id] = nil
        }
    }

    /// The sample a preview state shows: the HUD's for `.hud`; Now Playing, a meeting or a timer for the others.
    private func sampleActivity(for state: PreviewStageState) -> (ActivityID, any LiveActivity)? {
        let preferred: [ActivityID] = state == .hud ? [.hud] : [.nowPlaying, .meetingSoon, .timerRunning, .charging]
        let candidates = preferred.compactMap { registry.activity($0) }
            + (state == .hud ? [] : registry.activities.filter { $0.id != .hud && $0.id != .flash })
        for registered in candidates {
            if let sample = registered.makeSample?() { return (registered.id, sample) }
        }
        return nil
    }

    #if DEBUG
    /// Visual QA (`--qa-state`): force a state on the primary display, held open regardless of the pointer, shown
    /// even while the screen is locked (the screenshots are taken by window id).
    func forceQAState(_ state: QAHooks.State, page: PageID?) {
        guard let controller = primaryController else { log.error("QA: no panel"); return }
        qaForcesVisibility = true
        pointerDisplay = controller.key
        applyDisplayFacts()
        controller.viewModel.send(.hold("qa", true))
        switch state {
        case .closed:
            controller.viewModel.send(.close)
        case .compact:
            presentFlash(symbol: "hand.wave.fill", label: QAHooks.sampleLabel, duration: 3600, on: controller.key)
        case .peek:
            presentFlash(symbol: "hand.wave.fill", label: QAHooks.sampleLabel, duration: 3600, on: controller.key)
            controller.viewModel.send(.autoPeek(.flash, until: .infinity))
        case .open:
            controller.viewModel.send(.open(page: page, focus: nil, reason: .programmatic))
        case .calibrate:
            setCalibrating(true)
        }
    }
    #endif
}

private extension Duration {
    var seconds: TimeInterval { Double(components.seconds) + Double(components.attoseconds) / 1e18 }
}
