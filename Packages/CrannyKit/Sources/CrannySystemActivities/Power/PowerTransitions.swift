// CrannySystemActivities/Power/PowerTransitions.swift — the pure reducer that turns successive battery
// snapshots into activity events: power connected / disconnected and low-battery alerts (DESIGN.md §9.2).
// No clock, no I/O: unit-tested with snapshot sequences.
import Foundation

/// Something worth a live activity.
nonisolated enum PowerEvent: Equatable, Sendable {
    /// The adapter started (`connected`) or stopped providing power.
    case powerConnected
    case powerDisconnected
    /// The level reached `threshold` while on battery. `isFinal` = the lowest threshold (the alert stays).
    case lowBattery(threshold: Int, isFinal: Bool)
}

nonisolated struct PowerTransitions: Equatable, Sendable {
    /// A threshold alerts again only after the level rose this far above it (or power was connected),
    /// so a level that wobbles around 20 % never repeats the alert.
    static let rearmMargin = 3

    private(set) var last: BatteryState?
    /// Thresholds that can still alert.
    private(set) var armed: Set<Int> = []

    init() {}

    /// Feeds the next snapshot. The first snapshot (launch) and the first one with a battery never alert:
    /// they only decide which thresholds are already behind us.
    mutating func update(_ state: BatteryState, thresholds: LowBatteryThresholds) -> [PowerEvent] {
        let previous = last
        last = state
        guard state.hasBattery else { armed = []; return [] }
        guard let previous, previous.hasBattery else {
            armed = Self.unreached(by: state, thresholds)
            return []
        }

        var events: [PowerEvent] = []
        if !previous.isPluggedIn && state.isPluggedIn { events.append(.powerConnected) }
        if previous.isPluggedIn && !state.isPluggedIn { events.append(.powerDisconnected) }
        if state.isPluggedIn {
            armed = Set(thresholds.values)                       // a charge re-arms every warning
            return events
        }

        for threshold in thresholds.values where state.percent >= threshold + Self.rearmMargin {
            armed.insert(threshold)
        }
        let reached = thresholds.values.filter { armed.contains($0) && state.percent <= $0 }
        guard let lowest = reached.min() else { return events }
        armed.subtract(reached)
        let isFinal = lowest == thresholds.final
        // Unplugging below a first warning is not news; unplugging below the final warning is.
        if !events.contains(.powerDisconnected) || isFinal {
            events.append(.lowBattery(threshold: lowest, isFinal: isFinal))
        }
        return events
    }

    /// Settings changed the thresholds: thresholds already behind the current level stay quiet.
    mutating func reset(thresholds: LowBatteryThresholds) {
        guard let last, last.hasBattery else { armed = []; return }
        armed = Self.unreached(by: last, thresholds)
    }

    private static func unreached(by state: BatteryState, _ thresholds: LowBatteryThresholds) -> Set<Int> {
        Set(thresholds.values.filter { state.isPluggedIn || state.percent > $0 })
    }
}
