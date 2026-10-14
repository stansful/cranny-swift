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
    /// Bluetooth until `onLaunch`, and then only while the Settings ▸ Live Activities toggles want it.
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
        power.wantsSourcesChanged = { [weak accessories] in accessories?.wantsPowerSourceChanges ?? false }

        let charge = chargingKind, low = lowBatteryKind, devices = bluetoothKind
        registry.add(activity: charging, kind: charge, sample: { ChargingActivity.sample() })
        registry.add(activity: lowBattery, kind: low, sample: { LowBatteryActivity.sample() },
                     options: { AnyView(LowBatteryOptionsView(settings: services.settings)) })
        registry.add(activity: bluetooth, kind: devices, sample: { BluetoothActivity.sample() },
                     options: { AnyView(BluetoothOptionsView(settings: services.settings, permissions: services.permissions)) })
        registry.declare(.bluetooth, reason: SystemCopy.bluetoothPermissionReason,
                         optIn: SystemSettings.showsAllBluetoothDevices)   // onboarding asks only while it is on

        // Each model runs only while an activity it feeds is enabled (`ModelGate`). The power notifications also
        // refresh the batteries of a visible Bluetooth activity, so that toggle keeps the power model running too.
        let settings = services.settings
        let (chargeOn, lowOn, devicesOn) = (charge.isEnabledByDefault, low.isEnabledByDefault, devices.isEnabledByDefault)
        let powerGate = ModelGate(
            isEnabled: {
                ModelGate.isEnabled(.charging, byDefault: chargeOn, in: settings)
                    || ModelGate.isEnabled(.lowBattery, byDefault: lowOn, in: settings)
                    || ModelGate.isEnabled(.bluetoothDevice, byDefault: devicesOn, in: settings)
            },
            start: { power.start() }, stop: { power.stop() })
        let accessoryGate = ModelGate(
            isEnabled: { ModelGate.isEnabled(.bluetoothDevice, byDefault: devicesOn, in: settings) },
            start: { accessories.start() }, stop: { accessories.stop() })

        registry.onLaunch {
            #if DEBUG
            if let scenario = SystemQAScenario(arguments: CommandLine.arguments) {
                scenario.apply(charging: charging, lowBattery: lowBattery, bluetooth: bluetooth)
                return
            }
            #endif
            powerGate.open()
            accessoryGate.open()
        }
        registry.onTerminate {
            powerGate.close()
            accessoryGate.close()
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
