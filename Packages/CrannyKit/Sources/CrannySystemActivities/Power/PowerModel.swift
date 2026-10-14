// CrannySystemActivities/Power/PowerModel.swift — drives the Charging and Low battery activities from IOPS
// snapshots. Event-driven only (§9.2): a power-source notification → one off-main read → the pure
// `PowerTransitions` reducer → activity changes. Nothing runs while nothing changes.
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
    private(set) var state: BatteryState?

    private let settings: SettingsStore
    private let read: @Sendable () async -> BatteryState
    private let observer: (any PowerChangeObserving)?
    private var transitions = PowerTransitions()
    private var generation = 0
    private var thresholdsToken: ObservationToken?

    /// - Parameters:
    ///   - read: one snapshot of the battery (live: `PowerSources.snapshot`, off the main actor).
    ///   - observer: power-source notifications (live: `PowerObserver`; nil in tests, which call `apply`).
    init(settings: SettingsStore, charging: ChargingActivity, lowBattery: LowBatteryActivity,
         read: @escaping @Sendable () async -> BatteryState, observer: (any PowerChangeObserving)?) {
        self.settings = settings; self.charging = charging; self.lowBattery = lowBattery
        self.read = read; self.observer = observer
    }

    var thresholds: LowBatteryThresholds { LowBatteryThresholds(settings[SystemSettings.lowBatteryThresholds]) }
    /// How long a transient activity stays: the user's peek duration (time limits are adjustable, WCAG 2.2.1).
    var transientDuration: TimeInterval { max(settings[CoreSettings.peekDuration], 1) }

    func start() {
        observer?.start { [weak self] in
            self?.refresh()
            self?.onSourcesChanged?()
        }
        thresholdsToken = observe({ [settings] in settings[SystemSettings.lowBatteryThresholds] }) { [weak self] _ in
            self?.thresholdsChanged()
        }
        refresh()
    }

    func stop() {
        observer?.stop()
        thresholdsToken = nil
        generation += 1                                   // drops a read in flight
    }

    /// Reads a snapshot off the main actor; a newer refresh supersedes an older one still in flight.
    func refresh() {
        generation += 1
        let current = generation
        Task { [weak self, read] in
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
    }

    /// Keeps the final warning on screen while it applies, and removes any warning once power is connected.
    private func syncLowBattery(_ state: BatteryState, thresholds: LowBatteryThresholds) {
        let critical = thresholds.isCritical(state)
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
    }

    private func thresholdsChanged() {
        transitions.reset(thresholds: thresholds)
        if let state { syncLowBattery(state, thresholds: thresholds) }
    }
}
