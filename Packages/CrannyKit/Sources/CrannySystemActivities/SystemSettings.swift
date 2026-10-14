// CrannySystemActivities/SystemSettings.swift — the module's settings keys (ARCHITECTURE.md §10.11).
// There is no System pane: both keys are option rows under their activities in Settings ▸ Live Activities.
import CrannyCore
import Foundation

/// Settings of the system activities (namespace `system`).
public enum SystemSettings {
    /// Battery levels (percent) that raise the Low battery activity, any order. The lowest one is the final
    /// warning: below it the activity stays until power is connected (DESIGN.md §9.2).
    public static let lowBatteryThresholds = SettingKey<[Int]>(.system, "lowBatteryThresholds", default: [20, 10])
    /// Opt-in: also watch every Bluetooth device through IOBluetooth, which needs Bluetooth access.
    /// Off, only headphones (Core Audio) and Apple's Magic accessories (IOKit) are shown, with no prompt.
    public static let showsAllBluetoothDevices = SettingKey<Bool>(.system, "showsAllBluetoothDevices", default: false)
}

/// `SystemSettings.lowBatteryThresholds`, cleaned up: unique, 1…99 %, highest first.
nonisolated struct LowBatteryThresholds: Equatable, Sendable {
    /// Highest first.
    let values: [Int]

    init(_ raw: [Int]) {
        values = Set(raw.filter { (1...99).contains($0) }).sorted(by: >)
    }

    /// The lowest threshold: its alert stays while the Mac runs on battery at or below it.
    var final: Int? { values.last }
    /// The highest threshold when there is more than one (Settings shows it as "First warning").
    var firstWarning: Int? { values.count > 1 ? values.first : nil }

    /// True while the final warning must be visible: on battery at or below the final threshold.
    ///
    /// - Parameter shownFor: the final threshold the warning on screen was raised for, if any. While that is still
    ///   the final threshold, the warning keeps the hysteresis of `PowerTransitions`: it stays until power is
    ///   connected or the level rises `PowerTransitions.rearmMargin` above the threshold (exactly when the
    ///   threshold could alert again), so a level wobbling 10 ↔ 11 % never hides and re-shows it.
    func isCritical(_ state: BatteryState, shownFor: Int? = nil) -> Bool {
        guard let final, state.hasBattery, !state.isPluggedIn else { return false }
        let limit = shownFor == final ? final + PowerTransitions.rearmMargin - 1 : final
        return state.percent <= limit
    }

    /// The thresholds after Settings changed the first warning (nil = off). A first warning at or below the
    /// final one is dropped, so the final warning always stays the lowest value.
    func replacingFirstWarning(_ value: Int?) -> LowBatteryThresholds {
        let kept = values.count > 2 ? Array(values.dropFirst().dropLast()) : []
        let first = value.flatMap { $0 > (final ?? 0) ? $0 : nil }
        return LowBatteryThresholds([first].compactMap { $0 } + kept + [final].compactMap { $0 })
    }

    /// The thresholds after Settings changed the final warning; warnings at or below it are dropped.
    func replacingFinal(_ value: Int) -> LowBatteryThresholds {
        LowBatteryThresholds(values.dropLast().filter { $0 > value } + [value])
    }
}

// MARK: - Settings rows (main actor, like the setting key they read)

@MainActor extension LowBatteryThresholds {
    /// The defaults of `SystemSettings.lowBatteryThresholds` (first warning 20 %, final 10 %).
    static var defaults: LowBatteryThresholds { LowBatteryThresholds(SystemSettings.lowBatteryThresholds.defaultValue) }

    /// "First warning" ▸ Reset to Default: restores that row only; the final warning keeps its value.
    func resettingFirstWarning() -> LowBatteryThresholds { replacingFirstWarning(Self.defaults.firstWarning) }

    /// "Final warning" ▸ Reset to Default: restores that row only (a first warning still above it is kept).
    func resettingFinal() -> LowBatteryThresholds { Self.defaults.final.map(replacingFinal) ?? self }
}
