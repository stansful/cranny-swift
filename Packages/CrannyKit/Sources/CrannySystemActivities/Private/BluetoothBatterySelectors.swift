// CrannySystemActivities/Private/BluetoothBatterySelectors.swift — battery levels of an IOBluetooth device through
// the PRIVATE `batteryPercent*` selectors (ARCHITECTURE.md §7.12), for the opt-in "Show all Bluetooth devices"
// path only (`BluetoothDeviceWatcher`, which runs with Bluetooth access granted).
//
// Never linked: each selector is probed with `responds(to:)` before `value(forKey:)`. When a device answers none
// of them (the private API is gone), the device shows without battery levels and one `.info` line is logged per
// launch (§9.3). Works on any `NSObject`, so tests pass stand-ins instead of an `IOBluetoothDevice`.
import CrannyCore
import Foundation
import os

private let log = Log.logger(.bluetooth)

enum BluetoothBatterySelectors {
    static let single = "batteryPercentSingle"
    static let combined = "batteryPercentCombined"
    static let left = "batteryPercentLeft"
    static let right = "batteryPercentRight"
    static let chargingCase = "batteryPercentCase"
    static let all = [single, combined, left, right, chargingCase]

    /// Set once the missing selectors have been logged (one line per launch).
    private(set) static var hasReportedMissingSelectors = false

    /// The device's levels; 0 (the selectors' "unknown") and missing selectors read as no level.
    static func batteries(of device: NSObject) -> AccessoryBatteries {
        guard all.contains(where: { device.responds(to: NSSelectorFromString($0)) }) else {
            if !hasReportedMissingSelectors {
                hasReportedMissingSelectors = true
                log.info("IOBluetooth batteryPercent selectors unavailable: Bluetooth devices show without battery levels")
            }
            return .unknown
        }
        func level(_ selector: String) -> BatteryLevel? {
            guard device.responds(to: NSSelectorFromString(selector)),
                  let percent = (device.value(forKey: selector) as? NSNumber)?.intValue, percent > 0 else { return nil }
            return BatteryLevel(percent: percent)
        }
        return AccessoryBatteries(main: level(single) ?? level(combined), left: level(left), right: level(right),
                                  chargingCase: level(chargingCase))
    }
}
