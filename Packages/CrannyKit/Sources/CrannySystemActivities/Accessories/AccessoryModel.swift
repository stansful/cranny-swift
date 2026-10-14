// CrannySystemActivities/Accessories/AccessoryModel.swift — drives the Bluetooth activity (ARCHITECTURE.md §7.3).
// Connections come from the watchers' notifications; battery levels are read once when a device connects,
// a second after (levels often follow the connection) and every 60 s while the activity is visible — the
// only polling this module does (§9.2). The opt-in IOBluetooth watcher runs only with the setting on AND
// Bluetooth access granted; this model never asks for access itself.
import CrannyCore
import Foundation
import Observation
import os

private let log = Log.logger(.bluetooth)

@MainActor final class AccessoryModel {
    /// Battery levels often arrive a moment after the connection; then the 60-s visible refresh (§9.2).
    static let firstRefresh: TimeInterval = 1
    static let visibleRefresh: TimeInterval = 60

    let activity: BluetoothActivity
    private(set) var audio: [AudioOutputDevice] = []
    private(set) var hid: [HIDPeripheral] = []
    private(set) var bluetooth: [BluetoothDeviceInfo] = []
    private(set) var reports: [AccessoryBatteryReport] = []
    private(set) var isBluetoothWatcherRunning = false

    private let settings: SettingsStore
    private let permissions: PermissionsCenter
    private let hardware: any AccessoryHardware
    private var tracker = AccessoryTracker()
    private var refreshTask: Task<Void, Never>?
    private var refreshGeneration = 0
    private var bluetoothToken: ObservationToken?

    init(activity: BluetoothActivity, settings: SettingsStore, permissions: PermissionsCenter, hardware: any AccessoryHardware) {
        self.activity = activity; self.settings = settings; self.permissions = permissions; self.hardware = hardware
    }

    var transientDuration: TimeInterval { max(settings[CoreSettings.peekDuration], 1) }

    /// A battery refresh is pending (only while the activity is visible).
    private(set) var isRefreshScheduled = false

    /// Opted in and allowed: the IOBluetooth watcher may run.
    var wantsBluetoothWatcher: Bool {
        settings[SystemSettings.showsAllBluetoothDevices] && permissions.status(.bluetooth) == .granted
    }

    func start() {
        hardware.startWatching(audio: { [weak self] in self?.audioChanged($0) },
                               hid: { [weak self] in self?.hidChanged($0) })
        bluetoothToken = observe({ [weak self] in self?.wantsBluetoothWatcher ?? false }) { [weak self] wanted in
            self?.setBluetoothWatcher(running: wanted)
        }
        setBluetoothWatcher(running: wantsBluetoothWatcher)
    }

    func stop() {
        hardware.stopWatching()
        setBluetoothWatcher(running: false)
        bluetoothToken = nil
        refreshTask?.cancel()
        refreshTask = nil
    }

    // MARK: Source reports

    func audioChanged(_ devices: [AudioOutputDevice], now: Date = Date()) {
        audio = devices
        let new = tracker.newIDs(Set(devices.map(\.id)), from: .audio)
        for device in devices where new.contains(device.id) {
            connected(name: device.name, now: now) { AccessoryCatalog.accessory(audio: device, reports: $0) }
        }
        endIfGone()
    }

    func hidChanged(_ peripherals: [HIDPeripheral], now: Date = Date()) {
        hid = peripherals
        let new = tracker.newIDs(Set(peripherals.map { "\($0.id)" }), from: .hid)
        for peripheral in peripherals where new.contains("\(peripheral.id)") {
            connected(name: peripheral.name, now: now) { AccessoryCatalog.accessory(hid: peripheral, reports: $0) }
        }
        endIfGone()
    }

    func bluetoothChanged(_ devices: [BluetoothDeviceInfo], now: Date = Date()) {
        bluetooth = devices
        let new = tracker.newIDs(Set(devices.map(\.id)), from: .bluetooth)
        for device in devices where new.contains(device.id) {
            connected(name: device.name, now: now) { AccessoryCatalog.accessory(bluetooth: device, reports: $0) }
        }
        endIfGone()
    }

    /// A power-source notification: accessory levels may have changed. Read them only while they are shown.
    func powerSourcesChanged() {
        guard activity.isActive else { return }
        Task { [weak self] in await self?.refreshBatteries() }
    }

    // MARK: Showing

    /// Reads fresh battery levels, then shows the device (the same device seen by two sources shows once).
    private func connected(name: String, now: Date, build: @escaping @MainActor ([AccessoryBatteryReport]) -> Accessory) {
        guard tracker.shouldAnnounce(name: name, at: now) else { return }
        Task { [weak self] in
            guard let self else { return }
            reports = await hardware.batteryReports()
            let accessory = build(reports)
            guard isConnected(accessory.id) else { return }        // gone while the levels were read
            log.info("accessory connected: \(accessory.kind.rawValue, privacy: .public), battery known: \(!accessory.batteries.isEmpty, privacy: .public)")
            activity.present(accessory, for: transientDuration)
            scheduleVisibleRefresh()
        }
    }

    /// One sleep per refresh, and none past the activity: a transient activity (2.6 s) gets the 1-s refresh only.
    private func scheduleVisibleRefresh() {
        refreshTask?.cancel()
        refreshGeneration += 1
        let generation = refreshGeneration
        isRefreshScheduled = true
        refreshTask = Task { [weak self] in
            var delay = Self.firstRefresh
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(delay))
                guard let self, !Task.isCancelled, self.activity.isActive else { break }
                await self.refreshBatteries()
                if let expiresAt = self.activity.expiresAt, expiresAt.timeIntervalSinceNow < Self.visibleRefresh { break }
                delay = Self.visibleRefresh
            }
            if let self, self.refreshGeneration == generation { self.isRefreshScheduled = false }
        }
    }

    func refreshBatteries() async {
        guard activity.isActive else { return }
        reports = await hardware.batteryReports()
        let peripherals = await hardware.hidPeripherals()
        if !peripherals.isEmpty { hid = peripherals }
        if let shown = activity.accessory {
            activity.update(AccessoryCatalog.refreshed(shown, reports: reports, hid: hid, bluetooth: bluetooth))
        }
    }

    /// The device on screen disconnected: no reason to keep announcing it.
    private func endIfGone() {
        guard let shown = activity.accessory, !isConnected(shown.id) else { return }
        activity.end()
        refreshTask?.cancel()
    }

    /// Whether a source still lists the accessory (samples, shown by the QA hook, always count as connected).
    private func isConnected(_ id: String) -> Bool {
        id.hasPrefix("sample:")
            || audio.contains { "audio:\($0.id)" == id }
            || hid.contains { "hid:\($0.id)" == id }
            || bluetooth.contains { "bluetooth:\($0.id)" == id }
    }

    private func setBluetoothWatcher(running: Bool) {
        guard running != isBluetoothWatcherRunning else { return }
        isBluetoothWatcherRunning = running
        if running {
            log.info("starting the IOBluetooth watcher (opted in, access granted)")
            hardware.startBluetooth { [weak self] in self?.bluetoothChanged($0) }
        } else {
            hardware.stopBluetooth()
            bluetooth = []
            tracker.forget(.bluetooth)
        }
    }
}
