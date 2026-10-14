// CrannySystemActivities/SystemActivitiesModule.swift — the module's single entry point (ARCHITECTURE.md §3.4,
// §7.2–§7.3, §10.11): the Charging, Low battery and Bluetooth device live activities. No widget, no pane:
// the thresholds and "Show all Bluetooth devices" are option rows in Settings ▸ Live Activities.
import AppKit
import CrannyCore
import Foundation
import SwiftUI

/// Battery, charging and Bluetooth accessories as live activities. Registered by the shell's `CompositionRoot`.
public enum SystemActivitiesModule: FeatureModule {
    /// The module's settings namespace and owner tag (`.system`).
    public static var id: ModuleID { .system }

    /// Creates the models and contributes the three activities. Cheap: nothing touches IOKit, Core Audio or
    /// Bluetooth until `onLaunch`.
    public static func register(in registry: ModuleRegistry) {
        let services = registry.services
        let charging = ChargingActivity()
        let lowBattery = LowBatteryActivity(openBatterySettings: openBatterySettings)
        let bluetooth = BluetoothActivity()
        let power = PowerModel(settings: services.settings, charging: charging, lowBattery: lowBattery,
                               read: { await PowerSources.snapshot() }, observer: PowerObserver())
        let accessories = AccessoryModel(activity: bluetooth, settings: services.settings,
                                         permissions: services.permissions, hardware: LiveAccessoryHardware())
        power.onSourcesChanged = { [weak accessories] in accessories?.powerSourcesChanged() }

        registry.add(activity: charging, kind: chargingKind, sample: { ChargingActivity.sample() })
        registry.add(activity: lowBattery, kind: lowBatteryKind, sample: { LowBatteryActivity.sample() },
                     options: { AnyView(LowBatteryOptionsView(settings: services.settings)) })
        registry.add(activity: bluetooth, kind: bluetoothKind, sample: { BluetoothActivity.sample() },
                     options: { AnyView(BluetoothOptionsView(settings: services.settings, permissions: services.permissions)) })
        registry.declare(.bluetooth, reason: SystemCopy.bluetoothPermissionReason)

        registry.onLaunch {
            #if DEBUG
            if let scenario = SystemQAScenario(arguments: CommandLine.arguments) {
                scenario.apply(charging: charging, lowBattery: lowBattery, bluetooth: bluetooth)
                return
            }
            #endif
            power.start()
            accessories.start()
        }
        registry.onTerminate {
            power.stop()
            accessories.stop()
        }
    }

    // MARK: Kinds (Settings ▸ Live Activities)

    static var chargingKind: ActivityKind {
        ActivityKind(id: .charging, module: .system, title: SystemCopy.charging, symbol: "bolt.fill", defaultPriority: .alert)
    }
    static var lowBatteryKind: ActivityKind {
        ActivityKind(id: .lowBattery, module: .system, title: SystemCopy.lowBattery, symbol: "battery.25percent", defaultPriority: .alert)
    }
    static var bluetoothKind: ActivityKind {
        ActivityKind(id: .bluetoothDevice, module: .system, title: SystemCopy.bluetoothDevices, symbol: "headphones", defaultPriority: .alert)
    }

    /// System Settings ▸ Battery, where Low Power Mode lives (ARCHITECTURE.md D18; anchor [UNVERIFIED] on 27).
    static let batterySettingsURL = URL(string: "x-apple.systempreferences:com.apple.Battery-Settings.extension")

    static func openBatterySettings() {
        if let url = batterySettingsURL { NSWorkspace.shared.open(url) }
    }
}
