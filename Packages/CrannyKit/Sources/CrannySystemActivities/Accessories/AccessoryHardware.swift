// CrannySystemActivities/Accessories/AccessoryHardware.swift — the hardware behind the Bluetooth activity, as
// one injectable port: tests and previews pass `InertAccessoryHardware` (no IOKit, no Core Audio, no Bluetooth).
import CrannyCore
import Foundation

@MainActor protocol AccessoryHardware: AnyObject {
    /// Permission-free watchers (Core Audio, IOKit HID). Each first report is the baseline.
    func startWatching(audio: @escaping @MainActor ([AudioOutputDevice]) -> Void,
                       hid: @escaping @MainActor ([HIDPeripheral]) -> Void)
    func stopWatching()
    /// The opt-in IOBluetooth watcher. Call only with Bluetooth access granted.
    func startBluetooth(_ onChange: @escaping @MainActor ([BluetoothDeviceInfo]) -> Void)
    func stopBluetooth()
    /// Accessory batteries (private IOPS) and HID battery levels, read off the main actor.
    func batteryReports() async -> [AccessoryBatteryReport]
    func hidPeripherals() async -> [HIDPeripheral]
}

/// The real thing. Watchers deliver on their own queues; this hops their results to the main actor.
@MainActor final class LiveAccessoryHardware: AccessoryHardware {
    private var audioWatcher: AudioDeviceWatcher?
    private var hidWatcher: HIDPeripheralWatcher?
    private var bluetoothWatcher: BluetoothDeviceWatcher?
    /// Unstructured hops to the main actor may run out of order: only the newest report of a source counts.
    private var lastAudioReport = 0
    private var lastHIDReport = 0
    /// Bumped by every start and stop: a report still hopping from stopped watchers is dropped, so it can never
    /// stand in for the next start's baseline (the model restarts when its activity is turned back on).
    private var session = 0

    func startWatching(audio: @escaping @MainActor ([AudioOutputDevice]) -> Void,
                       hid: @escaping @MainActor ([HIDPeripheral]) -> Void) {
        guard audioWatcher == nil else { return }
        lastAudioReport = 0
        lastHIDReport = 0
        session += 1
        let session = session
        let audioWatcher = AudioDeviceWatcher { [weak self] number, devices in
            Task { @MainActor [weak self] in
                guard let self, session == self.session, number > self.lastAudioReport else { return }
                self.lastAudioReport = number
                audio(devices)
            }
        }
        let hidWatcher = HIDPeripheralWatcher { [weak self] number, peripherals in
            Task { @MainActor [weak self] in
                guard let self, session == self.session, number > self.lastHIDReport else { return }
                self.lastHIDReport = number
                hid(peripherals)
            }
        }
        audioWatcher.start()
        hidWatcher.start()
        self.audioWatcher = audioWatcher
        self.hidWatcher = hidWatcher
    }

    func stopWatching() {
        session += 1
        audioWatcher?.stop()
        hidWatcher?.stop()
        audioWatcher = nil
        hidWatcher = nil
    }

    func startBluetooth(_ onChange: @escaping @MainActor ([BluetoothDeviceInfo]) -> Void) {
        guard bluetoothWatcher == nil else { return }
        let watcher = BluetoothDeviceWatcher(onChange: onChange)
        bluetoothWatcher = watcher
        watcher.start()
    }

    func stopBluetooth() {
        bluetoothWatcher?.stop()
        bluetoothWatcher = nil
    }

    func batteryReports() async -> [AccessoryBatteryReport] { await AccessoryPowerSources.snapshot() }
    func hidPeripherals() async -> [HIDPeripheral] { await HIDPeripheralWatcher.snapshot() }
}

/// No hardware at all: previews, tests and the Settings stage.
@MainActor final class InertAccessoryHardware: AccessoryHardware {
    func startWatching(audio: @escaping @MainActor ([AudioOutputDevice]) -> Void,
                       hid: @escaping @MainActor ([HIDPeripheral]) -> Void) {}
    func stopWatching() {}
    func startBluetooth(_ onChange: @escaping @MainActor ([BluetoothDeviceInfo]) -> Void) {}
    func stopBluetooth() {}
    func batteryReports() async -> [AccessoryBatteryReport] { [] }
    func hidPeripherals() async -> [HIDPeripheral] { [] }
}
