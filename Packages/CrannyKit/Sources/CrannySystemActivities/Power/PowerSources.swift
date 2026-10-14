// CrannySystemActivities/Power/PowerSources.swift — live reads of the public IOPS API (R3 §2, verified on
// macOS 27). Every call is IPC to powerd, so callers read through `snapshot()`, off the main actor.
import Foundation
import IOKit.ps

nonisolated enum PowerSources {
    /// The internal battery right now (off the main actor).
    @concurrent static func snapshot() async -> BatteryState { readBattery() }

    /// Synchronous read; never call it on the main actor (use `snapshot()`).
    static func readBattery() -> BatteryState {
        let lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else {
            return .noBattery(isLowPowerMode: lowPower)
        }
        let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] ?? []
        let descriptions = list.compactMap { source in
            IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any]
        }
        let providing = IOPSGetProvidingPowerSourceType(blob)?.takeUnretainedValue() as String?
        let adapter = IOPSCopyExternalPowerAdapterDetails()?.takeRetainedValue() as? [String: Any]
        return BatteryState.parse(sources: descriptions, providingType: providing, adapter: adapter, isLowPowerMode: lowPower)
    }
}
