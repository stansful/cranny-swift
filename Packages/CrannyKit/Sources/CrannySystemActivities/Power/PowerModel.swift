// CrannySystemActivities/Power/PowerModel.swift — drives the Charging and Low battery activities from IOPS
// snapshots. Event-driven only (§9.2): a power-source notification → one off-main read (utility priority) →
// the pure `PowerTransitions` reducer → activity changes. Nothing runs while nothing changes.
//
// Energy: the observer reports every percent and estimate change only while the details matter
// (`wantsDetail`). A Mac with a battery on power, with nothing on screen that shows a percent or an estimate,
// hears only the switch to battery (and Low Power Mode): the thresholds re-arm while plugged in anyway, and
// the switch is what starts following again. The model runs only while Charging, Low battery or Bluetooth
// devices (whose visible batteries these notifications refresh) is enabled in Settings ▸ Live Activities.
import CrannyCore
import Foundation
import Observation
import os

private let log = Log.logger(.system)

@MainActor final class PowerModel {
    let charging: ChargingActivity
    let lowBattery: LowBatteryActivity
    /// Called after every power-source notification (the accessory model refreshes visible batteries).
    var onSourcesChanged: (@MainActor () -> Void)?
    /// Whether `onSourcesChanged` needs every percent and estimate change right now (the accessory model: while
    /// its activity shows batteries). Read through Observation: a change re-decides what the observer follows.
    var wantsSourcesChanged: (@MainActor () -> Bool)?
    private(set) var state: BatteryState?
    /// The observer reports every change (true from `start`, so nothing is missed before the first read).
    private(set) var followsDetail = true

    private let settings: SettingsStore
    /// `@concurrent`: the model, not each caller, guarantees the IPC read never runs on the main actor (§9.2).
    private let read: @concurrent @Sendable () async -> BatteryState
    private let observer: (any PowerChangeObserving)?
    private var transitions = PowerTransitions()
    /// The final threshold the persistent warning on screen belongs to (nil while none is shown).
    private var criticalThreshold: Int?
    private var generation = 0
    private var thresholdsToken: ObservationToken?
    private var detailToken: ObservationToken?

    /// - Parameters:
    ///   - read: one snapshot of the battery (live: `PowerSources.snapshot`); always runs off the main actor.
    ///   - observer: power-source notifications (live: `PowerObserver`; nil in tests, which call `apply`).
    init(settings: SettingsStore, charging: ChargingActivity, lowBattery: LowBatteryActivity,
         read: @escaping @concurrent @Sendable () async -> BatteryState, observer: (any PowerChangeObserving)?) {
        self.settings = settings; self.charging = charging; self.lowBattery = lowBattery
        self.read = read; self.observer = observer
    }

    var thresholds: LowBatteryThresholds { LowBatteryThresholds(settings[SystemSettings.lowBatteryThresholds]) }
    /// How long a transient activity stays: the user's peek duration (time limits are adjustable, WCAG 2.2.1).
    var transientDuration: TimeInterval { max(settings[CoreSettings.peekDuration], 1) }

    /// Whether the observer must report every percent and estimate change, or only the switches between AC and
    /// battery. On battery the thresholds need every percent. On power they re-arm whatever the level, so only
    /// what is on screen needs the details. A Mac without a battery keeps them all: IOKit can find the internal
    /// battery seconds into boot, and the switch notification does not report that.
    var wantsDetail: Bool {
        guard let state, state.hasBattery, state.isPluggedIn else { return true }
        return isShowingDetail
    }

    /// Something on screen shows what the details change: a battery activity, or the accessory model's batteries.
    private var isShowingDetail: Bool {
        charging.isActive || lowBattery.isActive || (wantsSourcesChanged?() ?? false)
    }

    /// Also a restart (Settings ▸ Live Activities): the first snapshot is a baseline again, as at launch.
    func start() {
        transitions = PowerTransitions()
        criticalThreshold = nil
        state = nil
        followsDetail = true
        observer?.start { [weak self] in
            self?.refresh()
            self?.onSourcesChanged?()
        }
        thresholdsToken = observe({ [settings] in settings[SystemSettings.lowBatteryThresholds] }) { [weak self] _ in
            self?.thresholdsChanged()
        }
        detailToken = observe({ [weak self] in self?.isShowingDetail ?? false }) { [weak self] _ in
            self?.syncDetail()
        }
        refresh()
    }

    /// Stops listening and hides both activities (nothing keeps them current any more).
    func stop() {
        observer?.stop()
        thresholdsToken = nil
        detailToken = nil
        generation += 1                                   // drops a read in flight
        charging.end()
        lowBattery.end()
    }

    /// Reads a snapshot off the main actor; a newer refresh supersedes an older one still in flight. Utility
    /// priority: the result only updates an activity, never a key or a click.
    func refresh() {
        generation += 1
        let current = generation
        Task(priority: .utility) { [weak self, read] in
            let state = await read()
            guard let self, current == self.generation else { return }
            self.apply(state)
        }
    }

    // MARK: Snapshot → activities

    func apply(_ state: BatteryState, now: Date = Date()) {
        if self.state?.hasBattery != state.hasBattery {
            log.info("battery present: \(state.hasBattery, privacy: .public)")
        }
        self.state = state
        let thresholds = thresholds
        for event in transitions.update(state, thresholds: thresholds) {
            switch event {
            case .powerConnected, .powerDisconnected:
                log.info("power \(event == .powerConnected ? "connected" : "disconnected", privacy: .public) at \(state.percent, privacy: .public) %")
                charging.present(ChargingContent(state), for: transientDuration, now: now)
            case .lowBattery(let threshold, let isFinal):
                log.info("low battery: reached \(threshold, privacy: .public) %")
                lowBattery.alert(LowBatteryContent(state, level: isFinal ? .critical : .warning),
                                 for: isFinal ? nil : transientDuration, now: now)
            }
        }
        if charging.isActive { charging.update(ChargingContent(state)) }
        syncLowBattery(state, thresholds: thresholds)
        syncDetail()
    }

    /// Keeps the final warning on screen while it applies, and removes any warning once power is connected.
    /// A final warning on screen keeps the reducer's hysteresis (`isCritical(_:shownFor:)`), so a level that
    /// wobbles across the threshold never makes it flicker; a changed final threshold is judged afresh.
    private func syncLowBattery(_ state: BatteryState, thresholds: LowBatteryThresholds) {
        let critical = thresholds.isCritical(state, shownFor: lowBattery.isPersistent ? criticalThreshold : nil)
        if critical {
            let content = LowBatteryContent(state, level: .critical)
            if lowBattery.isActive {
                lowBattery.update(content)
            } else {
                lowBattery.showQuietly(content)                 // launch below the final threshold: no peek
            }
        } else if lowBattery.isActive {
            if state.isPluggedIn || !state.hasBattery || lowBattery.isPersistent {
                lowBattery.end()
            } else if let content = lowBattery.content {
                lowBattery.update(LowBatteryContent(state, level: content.level))
            }
        }
        criticalThreshold = lowBattery.isPersistent ? thresholds.final : nil
    }

    private func thresholdsChanged() {
        transitions.reset(thresholds: thresholds)
        if let state { syncLowBattery(state, thresholds: thresholds) }
    }

    /// Tells the observer whether to follow every change (`wantsDetail`), after each snapshot and whenever what
    /// is on screen changes. Starting to follow reads once more: a change between the last read and the
    /// subscription would otherwise wait for the next one.
    private func syncDetail() {
        guard let observer else { return }
        let wanted = wantsDetail
        guard wanted != followsDetail else { return }
        followsDetail = wanted
        observer.setFollowsDetail(wanted)
        if wanted { refresh() }
    }
}
