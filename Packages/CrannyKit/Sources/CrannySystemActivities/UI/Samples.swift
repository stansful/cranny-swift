// CrannySystemActivities/UI/Samples.swift — self-contained sample activities for the Settings "Simulate"
// chips, the onboarding stage and `#Preview`s (ARCHITECTURE.md §3.6 `makeSample`). They never touch the real
// models and never expire.
import CrannyCore
import Foundation

extension ChargingActivity {
    static func sample(_ phase: ChargingContent.Phase = .charging) -> ChargingActivity {
        let activity = ChargingActivity()
        let content: ChargingContent = switch phase {
        case .charging: ChargingContent(phase: .charging, percent: 82, minutes: 80)
        case .charged: ChargingContent(phase: .charged, percent: 100)
        case .notCharging: ChargingContent(phase: .notCharging, percent: 80)
        case .onBattery: ChargingContent(phase: .onBattery, percent: 82, minutes: 250)
        }
        activity.present(content, for: nil)
        return activity
    }
}

extension LowBatteryActivity {
    static func sample(_ level: LowBatteryContent.Level = .critical, lowPowerMode: Bool = false) -> LowBatteryActivity {
        let activity = LowBatteryActivity(openBatterySettings: {})
        let content = switch level {
        case .critical: LowBatteryContent(level: .critical, percent: 10, minutesToEmpty: 35, isLowPowerMode: lowPowerMode)
        case .warning: LowBatteryContent(level: .warning, percent: 20, minutesToEmpty: 74, isLowPowerMode: lowPowerMode)
        }
        activity.alert(content, for: nil)
        return activity
    }
}

extension BluetoothActivity {
    /// AirPods Pro (left, right and case), Magic Trackpad (one battery) or headphones that report no battery.
    static func sample(_ kind: SampleDevice = .airPods) -> BluetoothActivity {
        let activity = BluetoothActivity()
        activity.present(kind.accessory, for: nil)
        return activity
    }

    enum SampleDevice: CaseIterable {
        case airPods, trackpad, headphones

        var accessory: Accessory {
            switch self {
            case .airPods:
                Accessory(id: "sample:airpods", name: "AirPods Pro", kind: .earbuds,
                          vendorID: DeviceSymbols.appleVendorID, productID: 0x2014,
                          batteries: AccessoryBatteries(main: BatteryLevel(percent: 82), left: BatteryLevel(percent: 84),
                                                        right: BatteryLevel(percent: 82), chargingCase: BatteryLevel(percent: 45)))
            case .trackpad:
                Accessory(id: "sample:trackpad", name: "Magic Trackpad", kind: .trackpad,
                          vendorID: DeviceSymbols.appleVendorID, productID: 0x0324,
                          batteries: AccessoryBatteries(main: BatteryLevel(percent: 64)))
            case .headphones:
                Accessory(id: "sample:headphones", name: SystemCopy.genericName(.headphones), kind: .headphones)
            }
        }
    }
}
