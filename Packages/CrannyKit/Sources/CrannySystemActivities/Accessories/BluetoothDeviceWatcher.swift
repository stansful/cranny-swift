// CrannySystemActivities/Accessories/BluetoothDeviceWatcher.swift — the OPT-IN "Show all Bluetooth devices"
// path (ARCHITECTURE.md §7.3): IOBluetooth connect/disconnect notifications for every device.
//
// IOBluetooth needs Bluetooth access (TCC). This watcher is created and started ONLY when
// `SystemSettings.showsAllBluetoothDevices` is on and `PermissionsCenter.status(.bluetooth) == .granted`; the
// prompt itself comes from `PermissionsCenter.request(.bluetooth)` behind the option's toggle. Battery levels
// use the PRIVATE `batteryPercent*` selectors (§7.12) through `Private/BluetoothBatterySelectors.swift`.
//
// Threading: IOBluetooth delivers its notifications on the run loop of the registering thread, the main
// thread here; the @objc handlers are main-actor methods.
import CrannyCore
import Foundation
import IOBluetooth
import os

private let log = Log.logger(.bluetooth)

/// A connected Bluetooth device reported by IOBluetooth.
nonisolated struct BluetoothDeviceInfo: Equatable, Sendable, Identifiable {
    /// The device address (never logged).
    var id: String
    var name: String
    var kind: AccessoryKind
    var batteries: AccessoryBatteries

    /// Class of Device → kind (Bluetooth Assigned Numbers; major 4 = audio, 5 = peripheral).
    static func kind(major: UInt32, minor: UInt32) -> AccessoryKind {
        switch major {
        case UInt32(kBluetoothDeviceClassMajorAudio):
            switch minor {
            case UInt32(kBluetoothDeviceClassMinorAudioLoudspeaker), UInt32(kBluetoothDeviceClassMinorAudioPortable),
                 UInt32(kBluetoothDeviceClassMinorAudioHiFi):
                return .speaker
            default:
                return .headphones
            }
        case UInt32(kBluetoothDeviceClassMajorPeripheral):
            switch minor & 0x0F {
            case UInt32(kBluetoothDeviceClassMinorPeripheral2Joystick), UInt32(kBluetoothDeviceClassMinorPeripheral2Gamepad):
                return .gameController
            default:
                break
            }
            switch minor & 0x30 {
            case UInt32(kBluetoothDeviceClassMinorPeripheral1Pointing): return .mouse
            case UInt32(kBluetoothDeviceClassMinorPeripheral1Keyboard), UInt32(kBluetoothDeviceClassMinorPeripheral1Combo): return .keyboard
            default: return .other
            }
        default:
            return .other
        }
    }
}

@MainActor final class BluetoothDeviceWatcher: NSObject {
    private let onChange: @MainActor ([BluetoothDeviceInfo]) -> Void
    private var connectNotification: IOBluetoothUserNotification?
    private var disconnectNotifications: [String: IOBluetoothUserNotification] = [:]
    private var devices: [String: BluetoothDeviceInfo] = [:]

    init(onChange: @escaping @MainActor ([BluetoothDeviceInfo]) -> Void) {
        self.onChange = onChange
    }

    /// Talks to bluetoothd: call only with Bluetooth access granted (see the top of the file).
    func start() {
        guard connectNotification == nil else { return }
        // The devices connected already form the baseline (the model's first report of this source). Registering
        // then also notifies them once more; they are known by then, so nothing is announced twice. A baseline
        // device is never shown from this report (only a new connection is), so its batteries are not read here:
        // each read is several private calls into bluetoothd, on the main actor.
        for case let device as IOBluetoothDevice in IOBluetoothDevice.pairedDevices() ?? [] where device.isConnected() {
            track(device, readsBatteries: false)
        }
        connectNotification = IOBluetoothDevice.register(forConnectNotifications: self, selector: #selector(connected(_:device:)))
        log.info("IOBluetooth watcher started")
        onChange(Array(devices.values))
    }

    func stop() {
        connectNotification?.unregister()
        connectNotification = nil
        for notification in disconnectNotifications.values { notification.unregister() }
        disconnectNotifications = [:]
        devices = [:]
    }

    // Main-actor @objc entry points: IOBluetooth calls them on the main run loop (see the top), and Swift 6
    // checks that isolation at the Objective-C boundary at run time (SE-0423).
    @objc private func connected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        add(device)
    }

    @objc private func disconnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        remove(device, notification: notification)
    }

    private func add(_ device: IOBluetoothDevice) {
        track(device)
        onChange(Array(devices.values))
    }

    /// - Parameter readsBatteries: false for the baseline, whose levels nobody shows (`.unknown` instead).
    private func track(_ device: IOBluetoothDevice, readsBatteries: Bool = true) {
        guard let address = device.addressString else { return }
        devices[address] = BluetoothDeviceInfo(
            id: address, name: device.name ?? "",
            kind: BluetoothDeviceInfo.kind(major: device.deviceClassMajor, minor: device.deviceClassMinor),
            batteries: readsBatteries ? BluetoothBatterySelectors.batteries(of: device) : .unknown)
        if disconnectNotifications[address] == nil {
            disconnectNotifications[address] = device.register(forDisconnectNotification: self, selector: #selector(disconnected(_:device:)))
        }
    }

    private func remove(_ device: IOBluetoothDevice, notification: IOBluetoothUserNotification) {
        notification.unregister()
        guard let address = device.addressString else { return }
        disconnectNotifications[address] = nil
        devices[address] = nil
        onChange(Array(devices.values))
    }
}
