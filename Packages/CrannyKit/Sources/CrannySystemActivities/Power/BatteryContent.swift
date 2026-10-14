// CrannySystemActivities/Power/BatteryContent.swift — what the Charging and Low battery activities draw:
// small value types derived from a `BatteryState`, so samples and tests need no hardware.
import Foundation

/// The Charging activity's content (shown 2.6 s on plug and unplug).
nonisolated struct ChargingContent: Equatable, Sendable {
    nonisolated enum Phase: Equatable, Sendable {
        case charging
        /// Full, on power.
        case charged
        /// On power but not charging (charge limit, optimized charging).
        case notCharging
        /// The adapter was just disconnected.
        case onBattery
    }

    var phase: Phase
    var percent: Int
    /// Minutes until full while charging, until empty on battery; nil while macOS estimates.
    var minutes: Int?

    init(phase: Phase, percent: Int, minutes: Int? = nil) {
        self.phase = phase; self.percent = percent; self.minutes = minutes
    }

    init(_ state: BatteryState) {
        percent = state.percent
        switch state.charge {
        case .charging:
            phase = .charging
            minutes = state.minutesToFull
        case .pluggedInNotCharging:
            phase = state.isCharged || state.percent >= 100 ? .charged : .notCharging
            minutes = nil
        case .discharging:
            phase = .onBattery
            minutes = state.minutesToEmpty
        }
    }

    var isOnPower: Bool { phase != .onBattery }
}

/// The Low battery activity's content.
nonisolated struct LowBatteryContent: Equatable, Sendable {
    nonisolated enum Level: Equatable, Sendable {
        /// A first warning (`warning` colour, shown for the peek duration).
        case warning
        /// At or below the final threshold (`danger` colour, stays until power is connected).
        case critical
    }

    var level: Level
    var percent: Int
    var minutesToEmpty: Int?
    var isLowPowerMode: Bool

    init(level: Level, percent: Int, minutesToEmpty: Int? = nil, isLowPowerMode: Bool = false) {
        self.level = level; self.percent = percent
        self.minutesToEmpty = minutesToEmpty; self.isLowPowerMode = isLowPowerMode
    }

    init(_ state: BatteryState, level: Level) {
        self.init(level: level, percent: state.percent, minutesToEmpty: state.minutesToEmpty,
                  isLowPowerMode: state.isLowPowerMode)
    }
}
