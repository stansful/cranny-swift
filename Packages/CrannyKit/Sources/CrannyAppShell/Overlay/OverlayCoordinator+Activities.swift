// CrannyAppShell/Overlay/OverlayCoordinator+Activities.swift — arbitration and per-display facts (ARCHITECTURE.md
// §4.6–§4.9). Two observations drive everything, no polling: the activities' snapshot (any observed property of any
// activity, or an arbitration setting, changed → `ActivityArbiter.update`) and the per-display facts (pointer display,
// environment, policy, per-display toggles → lineups and `NotchEnvironment`s). Expiry is ONE sleep to the earliest
// `expiresAt`. Peeks, VoiceOver announcements and delight moments follow from each update.
import AppKit
import CrannyCore
import CrannyNotchUI
import Foundation
import SwiftUI

extension OverlayCoordinator {
    /// Everything one arbitration reads (Equatable, so `observe` fires only on a real change).
    struct ArbitrationInput: Equatable {
        var activities: [ActivitySnapshot]
        var settings: ArbiterSettings
    }

    /// The per-display facts one display's lineup and environment derive from.
    struct DisplayFacts: Equatable {
        var filter: DisplayFilter
        var environment: NotchEnvironment
        var satellite: Bool
    }

    func startArbitration() {
        tokens.append(observe({ [weak self] in self?.arbitrationInput() }) { [weak self] input in
            if let input { self?.arbitrate(input) }
        })
        tokens.append(observe({ [weak self] in self?.allDisplayFacts() ?? [:] }) { [weak self] _ in self?.applyDisplayFacts() })
        // Song change while open: the tide or aurora ripples (§4.6 step 7).
        tokens.append(observe({ [weak self] in self?.registry.services.nowPlaying?.trackChangeCount ?? 0 }) { [weak self] _ in
            guard let self, let open = self.openController else { return }
            self.playDelight(.songRipple, on: open.key)
        })
        // Pausing silences activities: a flash shown just before must not come back when the pause ends. The flash
        // that confirms the pause is the exception (`outlastsPause`).
        tokens.append(observe({ [environment] in environment.areLiveActivitiesPaused }) { [weak self] paused in
            guard paused, let flash = self?.notchControl.flashActivity, !flash.outlastsPause else { return }
            flash.hide()
        })
        if let input = arbitrationInput() { arbitrate(input) }
    }

    // MARK: Arbitration

    func arbitrationInput() -> ArbitrationInput? {
        let settings = registry.services.settings
        let preferences = settings[CoreSettings.activityPreferences]
        let flash = notchControl.flashActivity
        let activities = registry.activities.enumerated().map { index, registered in
            let a = registered.activity
            let preference = preferences[registered.id]
            return ActivitySnapshot(
                id: registered.id, registrationIndex: index, isActive: a.isActive, priority: a.priority, slot: a.slot,
                revision: a.revision, expiresAt: a.expiresAt,
                isEnabled: preference?.isEnabled ?? registered.kind.isEnabledByDefault,
                peeksOnChange: preference?.peeksOnChange ?? registered.kind.peeksOnChangeByDefault, delight: a.delight,
                ignoresPause: registered.id == .flash && flash.outlastsPause)
        }
        return ArbitrationInput(activities: activities, settings: ArbiterSettings(
            order: settings[CoreSettings.activityOrder], paused: environment.areLiveActivitiesPaused,
            satellite: settings[CoreSettings.satellite], autoUnhide: settings[CoreSettings.autoUnhide]))
    }

    func arbitrate(_ input: ArbitrationInput) {
        let outcome = arbiter.update(input.activities, settings: input.settings, now: Date())
        ranked = outcome.ranked
        applyDisplayFacts()
        scheduleExpiry(outcome.nextExpiry)
        for controller in controllers.values where outcome.changed.contains(where: controller.viewModel.lineup.contains) {
            controller.viewModel.send(.activityChanged)
        }
        for id in outcome.peeks { requestAutoPeek(id) }
        for id in outcome.announcements { announce(id) }
        if let alert = alertController {
            for id in outcome.delights where alert.viewModel.lineup.primary == id || alert.viewModel.lineup.satellite == id {
                if let moment = registry.activity(id)?.activity.delight { playDelight(moment, on: alert.key) }
            }
        }
    }

    /// ONE wake-up at the earliest `expiresAt` (§4.6 step 6): transient activities hand the wings back on time.
    private func scheduleExpiry(_ date: Date?) {
        expiryTask?.cancel()
        guard let date else { return }
        expiryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(date.timeIntervalSinceNow, 0) + 0.01))
            guard !Task.isCancelled, let self, let input = self.arbitrationInput() else { return }
            self.arbitrate(input)
        }
    }

    // MARK: Per display

    func allDisplayFacts() -> [DisplayKey: DisplayFacts] {
        var facts: [DisplayKey: DisplayFacts] = [:]
        let satellite = registry.services.settings[CoreSettings.satellite]
        for key in controllers.keys {
            facts[key] = DisplayFacts(filter: displayFilter(for: key), environment: environmentFacts(for: key), satellite: satellite)
        }
        return facts
    }

    /// Pushes every display's environment and lineup (after arbitration, a rebuild or a facts change), and tells the
    /// HUD whether it would be drawn.
    func applyDisplayFacts() {
        let satellite = registry.services.settings[CoreSettings.satellite]
        for controller in controllers.values {
            controller.viewModel.setEnvironment(environmentFacts(for: controller.key))
            controller.viewModel.setLineup(arbiter.lineup(ranked, on: displayFilter(for: controller.key), satellite: satellite))
        }
        environment.setCanPresentHUD(canPresentHUD())
    }

    /// `SystemEnvironment.canPresentHUD`: the HUD goes to the alert display (the pointer's, else the primary one).
    /// It is drawn only if that display has a panel, keeps the HUD in its lineup and is not hidden. Otherwise the HUD
    /// leaves its keys to macOS, so its own HUD shows (D10: never none).
    func canPresentHUD() -> Bool {
        guard let key = alertController?.key else { return false }          // every chosen display is style Off
        return Self.canPresentHUD(filter: displayFilter(for: key), environment: environmentFacts(for: key))
    }

    /// Pure: the HUD survives this display's lineup filter and the panel is not hidden. The idle handle does not
    /// count: a new HUD revision brings it back.
    nonisolated static func canPresentHUD(filter: DisplayFilter, environment: NotchEnvironment) -> Bool {
        ActivityArbiter.showsHUD(on: filter) && environment.hardHidden == nil && !environment.notThisDisplay
    }

    func displayFilter(for key: DisplayKey) -> DisplayFilter {
        let preferences = registry.services.settings[CoreSettings.perDisplay][key] ?? DisplayPreferences()
        return DisplayFilter(key: key, isPointerDisplay: key == alertController?.key,
                             restrictsToAlerts: environmentFacts(for: key).restrictsToAlerts,
                             showsActivities: preferences.showsActivities, showsHUD: preferences.showsHUD,
                             flashDisplay: flashDisplay)
    }

    /// §4.8–§4.9 facts for one display: lock and sleep everywhere, full screen per display, the `.pointer` selection.
    func environmentFacts(for key: DisplayKey) -> NotchEnvironment {
        let settings = registry.services.settings
        let front = screens.first { $0.key == key }.map { environment.front(of: $0.id) } ?? FullScreenDetector.Front()
        var facts = NotchEnvironment(
            isLocked: environment.isScreenLocked, displaysAsleep: environment.areDisplaysAsleep,
            fullScreen: front.fullScreen, excludedApp: front.excludedApp,
            notThisDisplay: DisplayCatalog.followsPointer(settings[CoreSettings.displaySelection]) && pointerDisplay != nil
                && key != pointerDisplay,
            policy: settings[CoreSettings.fullScreenPolicy], demoMode: environment.isDemoMode)
        #if DEBUG
        if qaForcesVisibility { facts.isLocked = false; facts.displaysAsleep = false; facts.notThisDisplay = false }
        #endif
        return facts
    }

    /// Re-reads the window list and pushes the result now (hot key, auto-peek: §5.7 "lazily").
    func refreshEnvironmentNow() {
        environment.refreshFullScreen()
        applyDisplayFacts()
    }

    // MARK: Peeks, announcements, delights

    /// `ignoringPause`: the flash that confirms a pause or resume (it outlasts the pause it confirms).
    func requestAutoPeek(_ id: ActivityID, ignoringPause: Bool = false) {
        refreshEnvironmentNow()
        let preferences = registry.services.settings[CoreSettings.perDisplay]
        let displays = controllers.values.map { controller in
            PeekScheduler.Display(key: controller.key, isPointerDisplay: controller.key == alertController?.key,
                                  isOpen: controller.viewModel.state.isOpen, isHidden: controller.viewModel.state.hidden != nil,
                                  showsPeeks: preferences[controller.key]?.showsPeeks ?? true, lineup: controller.viewModel.lineup)
        }
        let paused = environment.areLiveActivitiesPaused && !ignoringPause
        guard let target = PeekScheduler.target(for: id, among: displays, paused: paused),
              let controller = controllers[target] else { return }
        let until = ProcessInfo.processInfo.systemUptime + registry.services.settings[CoreSettings.peekDuration]
        controller.viewModel.send(.autoPeek(id, until: until))
    }

    /// P1 alerts only, only while VoiceOver runs, through the app-wide limit of one alert or result per 10 s
    /// (`services.announcer`, DESIGN.md §16).
    private func announce(_ id: ActivityID) {
        guard NSWorkspace.shared.isVoiceOverEnabled, let activity = registry.activity(id)?.activity else { return }
        registry.services.announcer.announce(activity.accessibilityLabel, kind: .alert)
    }

    /// The caps of §4.6 step 7 (one at a time, not paused, not behind full screen, not on a hidden panel, not under
    /// Instant). Under Calm and Reduce Motion the scene plays the moment's reduced variant (DelightScheduler).
    func playDelight(_ moment: DelightMoment, on key: DisplayKey) {
        guard let controller = controllers[key] else { return }
        let front = screens.first { $0.key == key }.map { environment.front(of: $0.id) } ?? FullScreenDetector.Front()
        let gate = DelightScheduler.Gate(paused: environment.areLiveActivitiesPaused,
                                         fullScreenInFront: front.fullScreen || front.excludedApp,
                                         hidden: controller.viewModel.state.hidden != nil,
                                         motion: registry.services.settings[CoreSettings.motion],
                                         reduceMotion: environment.reduceMotion)
        guard delights.request(moment, now: ProcessInfo.processInfo.systemUptime, gate: gate) else { return }
        controller.viewModel.playDelight(moment)
    }

    // MARK: User actions on activities

    /// Swipe-up or VoiceOver "Dismiss": hidden until its next revision (§4.7).
    func dismiss(_ id: ActivityID) {
        guard let activity = registry.activity(id)?.activity else { return }
        arbiter.dismiss(id, revision: activity.revision)
        if let input = arbitrationInput() { arbitrate(input) }
    }

    /// Click on the satellite: it takes the wings (§4.4).
    func swapSatellite(on controller: NotchPanelController) {
        let lineup = controller.viewModel.lineup
        guard let primary = lineup.primary, let satellite = lineup.satellite else { return }
        arbiter.swapSatellite(primary: primary, satellite: satellite)
        applyDisplayFacts()
    }
}
