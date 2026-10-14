// CrannySystemActivities/Power/BatteryState.swift — one snapshot of the internal battery, parsed from the
// IOPS power-source descriptions (ARCHITECTURE.md §7.2, R3 §2). The parser is pure so tests feed it
// dictionaries captured from real Macs.
import Foundation
import IOKit.ps

/// What the battery activities know about the internal battery.
nonisolated struct BatteryState: Equatable, Sendable {
    /// Desktop Macs have no internal battery: every battery activity stays off.
    var hasBattery: Bool
    /// 0…100.
    var percent: Int
    /// The power adapter provides power (it may still not charge: charge limit, optimized charging).
    var isPluggedIn: Bool
    var isCharging: Bool
    /// Full while on power.
    var isCharged: Bool
    /// nil while macOS is still estimating, and on power.
    var minutesToEmpty: Int?
    /// nil while macOS is still estimating, and on battery.
    var minutesToFull: Int?
    var adapterWatts: Int?
    var isLowPowerMode: Bool

    init(hasBattery: Bool, percent: Int, isPluggedIn: Bool, isCharging: Bool = false, isCharged: Bool = false,
         minutesToEmpty: Int? = nil, minutesToFull: Int? = nil, adapterWatts: Int? = nil, isLowPowerMode: Bool = false) {
        self.hasBattery = hasBattery; self.percent = percent; self.isPluggedIn = isPluggedIn
        self.isCharging = isCharging; self.isCharged = isCharged
        self.minutesToEmpty = minutesToEmpty; self.minutesToFull = minutesToFull
        self.adapterWatts = adapterWatts; self.isLowPowerMode = isLowPowerMode
    }

    /// The three charge states of R3 §2 ("plugged in, not charging" is real: charge limit, optimized charging).
    nonisolated enum Charge: Equatable, Sendable { case charging, pluggedInNotCharging, discharging }

    var charge: Charge {
        if !isPluggedIn { return .discharging }
        return isCharging ? .charging : .pluggedInNotCharging
    }

    /// A Mac without an internal battery (or before the first read).
    static func noBattery(isPluggedIn: Bool = true, isLowPowerMode: Bool = false) -> BatteryState {
        BatteryState(hasBattery: false, percent: 0, isPluggedIn: isPluggedIn, isLowPowerMode: isLowPowerMode)
    }
}

// MARK: - Parsing IOPS descriptions

nonisolated extension BatteryState {
    /// Parses `IOPSGetPowerSourceDescription` dictionaries (all sources of `IOPSCopyPowerSourcesInfo`).
    /// - Parameters:
    ///   - sources: every power-source description; only the present internal battery is used.
    ///   - providingType: `IOPSGetProvidingPowerSourceType` ("AC Power", "Battery Power", "UPS Power").
    ///   - adapter: `IOPSCopyExternalPowerAdapterDetails`, if any.
    ///   - isLowPowerMode: `ProcessInfo.isLowPowerModeEnabled`.
    static func parse(sources: [[String: Any]], providingType: String?, adapter: [String: Any]?,
                      isLowPowerMode: Bool) -> BatteryState {
        let battery = sources.first { source in
            source[kIOPSTypeKey] as? String == kIOPSInternalBatteryType && (IOPSValue.bool(source[kIOPSIsPresentKey]) ?? true)
        }
        let acByProvider = providingType.map { $0 == kIOPSACPowerValue }
        guard let battery else {
            return .noBattery(isPluggedIn: acByProvider ?? true, isLowPowerMode: isLowPowerMode)
        }
        let current = IOPSValue.int(battery[kIOPSCurrentCapacityKey]) ?? 0
        let maximum = IOPSValue.int(battery[kIOPSMaxCapacityKey]) ?? 100
        let percent = maximum > 0 ? Int((Double(current) / Double(maximum) * 100).rounded()) : current
        let pluggedIn = acByProvider ?? (battery[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue)
        let charging = IOPSValue.bool(battery[kIOPSIsChargingKey]) ?? false
        // IOPS reports 0 or -1 while it is still estimating, and 0 for the direction that does not apply.
        let toEmpty = IOPSValue.int(battery[kIOPSTimeToEmptyKey]).flatMap { $0 > 0 ? $0 : nil }
        let toFull = IOPSValue.int(battery[kIOPSTimeToFullChargeKey]).flatMap { $0 > 0 ? $0 : nil }
        let lowPowerKey = IOPSValue.bool(battery["LPM Active"]) ?? false      // undocumented, seen on macOS 27
        return BatteryState(
            hasBattery: true,
            percent: min(max(percent, 0), 100),
            isPluggedIn: pluggedIn,
            isCharging: pluggedIn && charging,
            isCharged: pluggedIn && (IOPSValue.bool(battery[kIOPSIsChargedKey]) ?? false),
            minutesToEmpty: pluggedIn ? nil : toEmpty,
            minutesToFull: pluggedIn && charging ? toFull : nil,
            adapterWatts: adapter.flatMap { IOPSValue.int($0[kIOPSPowerAdapterWattsKey]) },
            isLowPowerMode: isLowPowerMode || lowPowerKey)
    }
}

/// IOPS values arrive as `NSNumber`s (CFNumber/CFBoolean); tests may also pass Swift `Int`/`Bool`.
nonisolated enum IOPSValue {
    static func int(_ value: Any?) -> Int? {
        switch value {
        case let number as NSNumber: number.intValue
        case let int as Int: int
        default: nil
        }
    }
    static func bool(_ value: Any?) -> Bool? {
        switch value {
        case let number as NSNumber: number.boolValue
        case let bool as Bool: bool
        case let int as Int: int != 0
        default: nil
        }
    }
}
