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
        // Pausing silences activities: a flash shown just before must not come back when the pause ends.
        tokens.append(observe({ [environment] in environment.areLiveActivitiesPaused }) { [weak self] paused in
            if paused { self?.notchControl.flashActivity.hide() }
        })
        if let input = arbitrationInput() { arbitrate(input) }
    }

    // MARK: Arbitration

    func arbitrationInput() -> ArbitrationInput? {
        let settings = registry.services.settings
        let preferences = settings[CoreSettings.activityPreferences]
        let activities = registry.activities.enumerated().map { index, registered in
            let a = registered.activity
            let preference = preferences[registered.id]
            return ActivitySnapshot(
                id: registered.id, registrationIndex: index, isActive: a.isActive, priority: a.priority, slot: a.slot,
                revision: a.revision, expiresAt: a.expiresAt,
                isEnabled: preference?.isEnabled ?? registered.kind.isEnabledByDefault,
                peeksOnChange: preference?.peeksOnChange ?? registered.kind.peeksOnChangeByDefault, delight: a.delight)
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

    /// Pushes every display's environment and lineup (after arbitration, a rebuild or a facts change).
    func applyDisplayFacts() {
        let satellite = registry.services.settings[CoreSettings.satellite]
        for controller in controllers.values {
            controller.viewModel.setEnvironment(environmentFacts(for: controller.key))
            controller.viewModel.setLineup(arbiter.lineup(ranked, on: displayFilter(for: controller.key), satellite: satellite))
        }
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

    func requestAutoPeek(_ id: ActivityID) {
        refreshEnvironmentNow()
        let preferences = registry.services.settings[CoreSettings.perDisplay]
        let displays = controllers.values.map { controller in
            PeekScheduler.Display(key: controller.key, isPointerDisplay: controller.key == alertController?.key,
                                  isOpen: controller.viewModel.state.isOpen, isHidden: controller.viewModel.state.hidden != nil,
                                  showsPeeks: preferences[controller.key]?.showsPeeks ?? true, lineup: controller.viewModel.lineup)
        }
        guard let target = PeekScheduler.target(for: id, among: displays, paused: environment.areLiveActivitiesPaused),
              let controller = controllers[target] else { return }
        let until = ProcessInfo.processInfo.systemUptime + registry.services.settings[CoreSettings.peekDuration]
        controller.viewModel.send(.autoPeek(id, until: until))
    }

    /// P1 alerts only, ≤ 1 per 10 s, only while VoiceOver runs (DESIGN.md §16).
    private func announce(_ id: ActivityID) {
        guard NSWorkspace.shared.isVoiceOverEnabled, let activity = registry.activity(id)?.activity,
              announcements.allow(now: ProcessInfo.processInfo.systemUptime) else { return }
        AccessibilityNotification.Announcement(activity.accessibilityLabel).post()
    }

    /// The caps of §4.6 step 7 (one at a time, not paused, not behind full screen, not on a hidden panel, not
    /// Calm/Instant/Reduce Motion).
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
