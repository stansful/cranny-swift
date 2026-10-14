// CrannyHUD/Model/HUDController.swift — the HUD's main-actor façade (ARCHITECTURE.md §7.1). It turns settings,
// the Accessibility grant and the environment into the tap's config snapshot, installs or removes the tap,
// runs `HUDPresentation` on what the tap reports and executes the effects: the activity, one hide sleep per
// session, the `.levelChange` haptic, the feedback sound and the settled VoiceOver announcement.
//
// Energy (§9.2): with "Replace the system HUD" off nothing runs. On, the tap thread sleeps in its run loop and
// the CoreAudio listener is event-driven; the only timer-like work is the hide sleep, the 0.5-s announcement
// settle and the 2-Hz brightness poll, all only while a HUD is visible.
import AppKit
import CrannyCore
import Foundation
import Observation
import os
import SwiftUI

private let log = Log.logger(.hud)

@MainActor @Observable final class HUDController {
    /// The event tap is installed (Settings ▸ HUD status).
    private(set) var isTapRunning = false
    /// The config wanted a tap but macOS refused to create it (Settings ▸ HUD explains).
    private(set) var tapFailed = false

    @ObservationIgnored let activity: HUDActivity
    @ObservationIgnored private let services: CrannyServices
    @ObservationIgnored private let hardware: HUDHardware
    @ObservationIgnored private let accessibility: HUDAccessibility
    @ObservationIgnored private let feedback: FeedbackSound
    @ObservationIgnored private let configBox = HUDTapConfigBox()
    @ObservationIgnored private lazy var handler = MediaKeyHandler(
        config: configBox, volume: hardware.volume, brightness: hardware.brightness, keyboard: hardware.keyboard,
        sink: { [weak self] signal in Task { @MainActor in self?.receive(signal) } })
    @ObservationIgnored private var interceptor: (any KeyInterceptor)?
    @ObservationIgnored private var volumeObserver: (any VolumeObserving)?
    @ObservationIgnored private var tokens: [ObservationToken] = []
    @ObservationIgnored private var activationObserver: (any NSObjectProtocol)?
    @ObservationIgnored private var state = HUDPresentationState()
    @ObservationIgnored private lazy var hideTimer = MovableDeadline(now: { [weak self] in self?.now() ?? Date() })
    @ObservationIgnored private lazy var announceTimer = MovableDeadline(now: { [weak self] in self?.now() ?? Date() })
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var lastPress = Date.distantPast
    /// The clock of sessions and deadlines (tests freeze it; sleeps still use real time).
    @ObservationIgnored var now: @MainActor () -> Date = { Date() }
    /// The grant as last applied (nil before `start()`): a false → true transition turns the HUD on.
    @ObservationIgnored private var lastAccessibilityGranted: Bool?

    /// After a press, the output's own report of the level is ignored this long (only a device change counts):
    /// it echoes the write, and a Bluetooth output may still report the old level then.
    static let volumeEchoWindow: TimeInterval = 0.4

    /// `accessibility` defaults to the Core permissions center (tests inject their own).
    init(services: CrannyServices, activity: HUDActivity, hardware: HUDHardware,
         accessibility: HUDAccessibility? = nil, feedback: FeedbackSound = FeedbackSound()) {
        self.services = services
        self.activity = activity
        self.hardware = hardware
        self.accessibility = accessibility ?? .live(services.permissions)
        self.feedback = feedback
        activity.adjust = { [weak self] kind, action in
            guard let handler = self?.handler else { return }
            Task { await Self.adjust(handler, kind, action) }
        }
    }

    /// From `registry.onLaunch`: follow the inputs of the tap config from now on.
    func start() {
        guard tokens.isEmpty else { return }
        tokens.append(observe({ [weak self] in self?.configInputs() }) { [weak self] inputs in
            if let inputs { self?.apply(inputs) }
        })
        apply(configInputs())
        // Accessibility changes do not notify: re-check the grant each time the user comes back to Cranny (e.g.
        // from System Settings to Settings ▸ HUD), whatever the toggle says. One call per activation; no polling.
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkAccessibility() }     // queue: .main
        }
    }

    /// From `registry.onTerminate`: remove the tap and the listener (keys go back to macOS at once).
    func stop() {
        tokens.removeAll()
        if let activationObserver { NotificationCenter.default.removeObserver(activationObserver) }
        activationObserver = nil
        configBox.update(.off)
        stopTap()
        stopVolumeObserver()
        endSession()
    }

    // MARK: Config

    /// What the tap config depends on, read from observable sources (settings, permissions, environment).
    func configInputs() -> HUDTapConfig.Inputs {
        let settings = services.settings
        let environment = services.environment
        return HUDTapConfig.Inputs(
            replaceSystemHUD: settings[HUDSettings.replaceSystemHUD],
            volume: settings[HUDSettings.volume],
            brightness: settings[HUDSettings.brightness],
            keyboardBacklight: settings[HUDSettings.keyboardBacklight],
            activityEnabled: HUDActivity.isEnabled(in: settings),
            accessibilityGranted: accessibility.isGranted(),
            screenLocked: environment.isScreenLocked,
            displaysAsleep: environment.areDisplaysAsleep,
            fullScreenInFront: environment.isFullScreenInFront,
            fullScreenPolicy: settings[CoreSettings.fullScreenPolicy],
            shellCanPresentHUD: environment.canPresentHUD)
    }

    private func apply(_ inputs: HUDTapConfig.Inputs) {
        var inputs = inputs
        if lastAccessibilityGranted == false, inputs.accessibilityGranted, !inputs.replaceSystemHUD,
           !services.settings[HUDSettings.turnedOffByUser] {
            // Accessibility arrived while Cranny runs (onboarding's "Allow", or System Settings after Settings ▸ HUD).
            // Cranny asks for it only for the HUD, so the grant means "replace the system HUD" — unless the user
            // turned the HUD off in Settings ▸ HUD: then a later grant (e.g. re-granting after a TCC reset, §11.1
            // risk 5) keeps it off. A grant that already existed at launch changes nothing. (Applied here too: a
            // write inside the observer's callback is not reported back to it.)
            log.info("Accessibility granted: turning on the HUD replacement")
            services.settings[HUDSettings.replaceSystemHUD] = true
            inputs.replaceSystemHUD = true
        }
        lastAccessibilityGranted = inputs.accessibilityGranted
        let config = HUDTapConfig(inputs)
        configBox.update(config)
        if config.wantsTap { startTap() } else { stopTap() }
        if config.handlesVolume { startVolumeObserver() } else { stopVolumeObserver() }
        if !config.isReplacing || !config.isPresentable { endSession() }
    }

    private func startTap() {
        guard interceptor == nil else { return }
        let tap = hardware.makeInterceptor(handler)
        if tap.start() {
            interceptor = tap
            isTapRunning = true
            if tapFailed { tapFailed = false }
        } else {
            tapFailed = true
            // The grant was revoked since it was last read: refresh, which turns the config off.
            log.error("event tap could not be created although Accessibility was reported granted")
            accessibility.refresh()
        }
    }

    private func stopTap() {
        interceptor?.stop()
        interceptor = nil
        if isTapRunning { isTapRunning = false }
        if tapFailed { tapFailed = false }
    }

    private func startVolumeObserver() {
        guard volumeObserver == nil else { return }
        let observer = hardware.makeVolumeObserver()
        observer.start { [weak self] observation in Task { @MainActor in self?.observed(observation) } }
        volumeObserver = observer
    }

    private func stopVolumeObserver() {
        volumeObserver?.stop()
        volumeObserver = nil
    }

    /// The user came back to Cranny, or macOS disabled the tap: if macOS's answer differs from the cached grant —
    /// granted in System Settings, or revoked while the tap ran — refresh it. The config follows by observation
    /// (a revoked grant removes the tap, so Settings ▸ HUD stops saying "Cranny handles the keys now").
    func checkAccessibility() {
        guard accessibility.isStale else { return }
        log.info("Accessibility changed outside Cranny; refreshing")
        accessibility.refresh()
    }

    // MARK: Signals from the tap (main actor)

    func receive(_ signal: HUDSignal) {
        switch signal {
        case .changed(let update):
            let duration = HUDSettings.clampedDuration(services.settings[HUDSettings.duration])
            let (next, effects) = HUDPresentation.receive(update, state: state, now: now(), duration: duration)
            guard next != state else { return }
            state = next
            lastPress = now()
            activity.present(state.session)
            perform(effects)
            updateBrightnessPolling()
        case .volumeKeyReleased(let shiftHeld):
            feedback.keyReleased(shiftHeld: shiftHeld, demoMode: services.environment.isDemoMode,
                                 muted: state.session?.display.isMuted ?? false)
        case .tapDisabled:
            checkAccessibility()                 // macOS may have disabled it because the grant was revoked
        }
    }

    private func observed(_ observation: VolumeObservation) {
        guard observation.deviceChanged || now().timeIntervalSince(lastPress) >= Self.volumeEchoWindow else { return }
        let next = HUDPresentation.observe(observation, state: state, now: now(),
                                           showsOutputDevice: services.settings[HUDSettings.showsOutputDevice])
        guard next != state else { return }
        state = next
        if state.session?.isVisible(at: now()) == true { activity.present(state.session) }
    }

    private func observedBrightness(_ level: Double) {
        guard now().timeIntervalSince(lastPress) > 0.75 else { return }   // the panel may still be fading to our level
        let next = HUDPresentation.observeBrightness(level, state: state, now: now())
        guard next != state else { return }
        state = next
        activity.present(state.session)
    }

    // MARK: Effects

    private func perform(_ effects: [HUDEffect]) {
        for effect in effects {
            switch effect {
            case .levelChangeHaptic: services.haptics.play(.levelChange)
            case .scheduleHide(let deadline): scheduleHide(at: deadline)
            case .announceWhenSettled: scheduleAnnouncement()
            }
        }
    }

    /// One sleep per session; a press only moves the deadline (no task per key repeat).
    private func scheduleHide(at deadline: Date) {
        hideTimer.schedule(at: deadline) { [weak self] in self?.hideExpired() }
    }

    private func hideExpired() {
        state = HUDPresentation.hide(state, now: now())
        if state.session == nil { endSession() }
    }

    /// Hides the HUD now and cancels everything that only runs while it is visible.
    private func endSession() {
        state.session = nil
        hideTimer.cancel()
        announceTimer.cancel()
        activity.present(nil)
        updateBrightnessPolling()
    }

    /// DESIGN.md §16: "Volume, 62 %" once the value has settled for 0.5 s, only while VoiceOver runs.
    private func scheduleAnnouncement() {
        guard NSWorkspace.shared.isVoiceOverEnabled else { return }
        announceTimer.schedule(at: now().addingTimeInterval(0.5)) { [weak self] in self?.announce() }
    }

    private func announce() {
        guard let display = state.session?.display, NSWorkspace.shared.isVoiceOverEnabled else { return }
        AccessibilityNotification.Announcement(HUDCopy.announcement(display)).post()
    }

    /// Brightness changed elsewhere (ambient light, Control Center) follows the visible brightness HUD: 2 Hz,
    /// only while it is visible (the one polling ARCHITECTURE.md §9.2 allows the HUD).
    private func updateBrightnessPolling() {
        let wantsPolling = state.session?.display.kind == .brightness
        guard wantsPolling != (pollTask != nil) else { return }
        guard wantsPolling else {
            pollTask?.cancel()
            pollTask = nil
            return
        }
        let brightness = hardware.brightness
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled, self != nil else { return }
                if let level = await Self.readLevel(brightness) { self?.observedBrightness(level) }
            }
        }
    }

    /// DisplayServices may talk to the backlight daemon: read it off the main actor.
    @concurrent private static func readLevel(_ brightness: any DisplayBrightness) async -> Double? {
        brightness.readLevel()
    }

    /// VoiceOver Increase / Decrease / Mute touch the same devices as a key (CoreAudio, DisplayServices,
    /// CoreBrightness): off the main actor too. The handler reports back through its sink like a key press.
    @concurrent private static func adjust(_ handler: MediaKeyHandler, _ kind: HUDKind, _ action: LevelAction) async {
        handler.adjust(kind, action)
    }

    // MARK: Visual QA (Debug builds only, `--qa-hud`)

    #if DEBUG
    /// Shows `display` for an hour without touching any device or the tap.
    func presentForQA(_ display: HUDDisplay) {
        state.revision += 1
        state.session = HUDSession(display: display, deadline: now().addingTimeInterval(3600),
                                   revision: state.revision, sequence: 0)
        activity.present(state.session)
    }
    #endif
}
