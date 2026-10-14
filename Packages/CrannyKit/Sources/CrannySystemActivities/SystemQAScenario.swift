// CrannySystemActivities/SystemQAScenario.swift — DEBUG-only visual QA (docs/CONTRIBUTING.md "Visual QA hooks"):
//
//   --qa-system charging|charged|plugged|unplugged|warning|critical|airpods|trackpad|headphones
//
// shows that activity with sample data on the REAL activity objects, held until quit, so the shell's own
// arbitration puts it in the band (screenshot the panel by window id). The power and accessory models are not
// started in this mode, so no real plug event interferes. Compiled out of Release builds.
#if DEBUG
import CrannyCore
import Foundation

enum SystemQAScenario: String, CaseIterable {
    case charging, charged, plugged, unplugged, warning, critical, airpods, trackpad, headphones

    init?(arguments: [String]) {
        guard let scenario = LaunchArguments(arguments).value(after: "--qa-system").flatMap(SystemQAScenario.init(rawValue:))
        else { return nil }
        self = scenario
    }

    func apply(charging: ChargingActivity, lowBattery: LowBatteryActivity, bluetooth: BluetoothActivity) {
        switch self {
        case .charging: charging.present(ChargingContent(phase: .charging, percent: 82, minutes: 80), for: nil)
        case .charged: charging.present(ChargingContent(phase: .charged, percent: 100), for: nil)
        case .plugged: charging.present(ChargingContent(phase: .notCharging, percent: 80), for: nil)
        case .unplugged: charging.present(ChargingContent(phase: .onBattery, percent: 82, minutes: 250), for: nil)
        case .warning: lowBattery.alert(LowBatteryContent(level: .warning, percent: 20, minutesToEmpty: 74), for: nil)
        case .critical: lowBattery.alert(LowBatteryContent(level: .critical, percent: 10, minutesToEmpty: 35), for: nil)
        case .airpods: bluetooth.present(BluetoothActivity.SampleDevice.airPods.accessory, for: nil)
        case .trackpad: bluetooth.present(BluetoothActivity.SampleDevice.trackpad.accessory, for: nil)
        case .headphones: bluetooth.present(BluetoothActivity.SampleDevice.headphones.accessory, for: nil)
        }
    }
}
#endif
