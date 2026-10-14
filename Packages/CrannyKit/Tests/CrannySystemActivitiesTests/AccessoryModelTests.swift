// The Bluetooth activity driven by fake hardware: connect → one transient activity with fresh levels; the
// opt-in IOBluetooth watcher only with the setting on AND access granted.
import CrannyCore
import Foundation
import Testing
@testable import CrannySystemActivities

@MainActor final class FakeAccessoryHardware: AccessoryHardware {
    var audio: (@MainActor ([AudioOutputDevice]) -> Void)?
    var hid: (@MainActor ([HIDPeripheral]) -> Void)?
    var bluetooth: (@MainActor ([BluetoothDeviceInfo]) -> Void)?
    var reports: [AccessoryBatteryReport] = []
    var peripherals: [HIDPeripheral] = []
    private(set) var batteryReads = 0
    private(set) var calls: [String] = []

    func startWatching(audio: @escaping @MainActor ([AudioOutputDevice]) -> Void, hid: @escaping @MainActor ([HIDPeripheral]) -> Void) {
        calls.append("watch"); self.audio = audio; self.hid = hid
    }
    func stopWatching() { calls.append("unwatch") }
    func startBluetooth(_ onChange: @escaping @MainActor ([BluetoothDeviceInfo]) -> Void) { calls.append("bluetooth"); bluetooth = onChange }
    func stopBluetooth() { calls.append("no-bluetooth"); bluetooth = nil }
    func batteryReports() async -> [AccessoryBatteryReport] { batteryReads += 1; return reports }
    func hidPeripherals() async -> [HIDPeripheral] { peripherals }
}

@MainActor @Suite struct AccessoryModelTests {
    let services = CrannyServices.preview()
    let activity = BluetoothActivity()
    let hardware = FakeAccessoryHardware()

    private func makeModel() -> AccessoryModel {
        AccessoryModel(activity: activity, settings: services.settings, permissions: services.permissions, hardware: hardware)
    }
    private func settle(until condition: () -> Bool) async {
        for _ in 0..<200 where !condition() { await Task.yield() }
    }
    private func airPodsReports() throws -> [AccessoryBatteryReport] {
        AccessoryPowerSources.group(AccessoryPowerSources.parse(try [Fixtures.airPodsCase, Fixtures.airPodsBuds].map(Fixtures.dictionary)))
    }

    @Test func devicesAlreadyConnectedAtLaunchAreNotAnnounced() async {
        let model = makeModel()
        model.start()
        defer { model.stop() }
        hardware.audio?([AudioOutputDevice(id: "1", name: "AirPods")])
        hardware.hid?([HIDPeripheral(id: 2, name: "Magic Keyboard", category: "Keyboard", vendorID: 76, productID: 1, batteryPercent: 80)])
        await settle { false }
        #expect(!activity.isActive)
        #expect(hardware.batteryReads == 0)                 // nothing read while nothing is shown
    }

    @Test func connectingHeadphonesShowsThemWithFreshLevels() async throws {
        let model = makeModel()
        model.start()
        defer { model.stop() }
        hardware.audio?([])
        hardware.reports = try airPodsReports()
        hardware.audio?([AudioOutputDevice(id: "1", name: "AirPods")])
        await settle { activity.isActive }
        #expect(activity.revision == 1)
        #expect(activity.priority == .alert)
        #expect(activity.accessory?.batteries.left?.percent == 84)
        #expect(activity.expiresAt != nil)
        #expect(hardware.batteryReads == 1)
    }

    @Test func theSameDeviceFromTwoSourcesShowsOnce() async {
        services.permissions.record(.granted, for: .bluetooth)
        services.settings[SystemSettings.showsAllBluetoothDevices] = true
        let model = makeModel()
        model.start()
        defer { model.stop() }
        hardware.audio?([])
        hardware.bluetooth?([])
        hardware.audio?([AudioOutputDevice(id: "1", name: "AirPods")])
        hardware.bluetooth?([BluetoothDeviceInfo(id: "aa", name: "AirPods", kind: .headphones, batteries: .unknown)])
        await settle { activity.isActive }
        await settle { false }
        #expect(activity.revision == 1)
    }

    @Test func disconnectingEndsTheActivity() async {
        let model = makeModel()
        model.start()
        defer { model.stop() }
        hardware.hid?([])
        let keyboard = HIDPeripheral(id: 5, name: "Magic Keyboard", category: "Keyboard", vendorID: 76, productID: 1, batteryPercent: 80)
        hardware.hid?([keyboard])
        await settle { activity.isActive }
        #expect(activity.accessory?.symbol == "keyboard")
        #expect(activity.accessory?.batteries.main?.percent == 80)
        hardware.hid?([])
        #expect(!activity.isActive)
    }

    @Test func transientActivityGetsOnlyTheFirstRefresh() async {
        services.settings[CoreSettings.peekDuration] = 30          // shorter than the 60-s refresh, longer than the test
        let model = makeModel()
        model.start()
        defer { model.stop() }
        hardware.audio?([])
        hardware.audio?([AudioOutputDevice(id: "1", name: "AirPods")])
        await settle { activity.isActive }
        let start = Date()
        while model.isRefreshScheduled && Date().timeIntervalSince(start) < 10 { try? await Task.sleep(for: .milliseconds(50)) }
        #expect(!model.isRefreshScheduled)
        #expect(hardware.batteryReads == 2)                 // on connect, then once a second later
        #expect(activity.isActive)                          // still on screen, yet nothing else is scheduled
    }

    @Test func levelsRefreshWhileVisible() async throws {
        let model = makeModel()
        model.start()
        defer { model.stop() }
        hardware.audio?([])
        hardware.audio?([AudioOutputDevice(id: "1", name: "AirPods")])
        await settle { activity.isActive }
        #expect(activity.accessory?.batteries.isEmpty == true)
        hardware.reports = try airPodsReports()
        model.powerSourcesChanged()                          // an IOPS notification while visible
        await settle { activity.accessory?.batteries.isEmpty == false }
        #expect(activity.accessory?.batteries.right?.percent == 81)
        #expect(activity.revision == 1)                      // new levels are not a new connection
    }

    @Test func refreshStopsWithTheActivity() async {
        let model = makeModel()
        model.start()
        defer { model.stop() }
        hardware.audio?([])
        hardware.audio?([AudioOutputDevice(id: "1", name: "AirPods")])
        await settle { activity.isActive }
        #expect(model.isRefreshScheduled)
        activity.end()
        let start = Date()
        while model.isRefreshScheduled && Date().timeIntervalSince(start) < 10 { try? await Task.sleep(for: .milliseconds(50)) }
        #expect(!model.isRefreshScheduled)                  // the 1-s wake-up saw it gone; no 60-s wake-up follows
    }

    @Test func aRestartStartsFromABaseline() async {
        let model = makeModel()
        model.start()
        hardware.audio?([])
        hardware.audio?([AudioOutputDevice(id: "1", name: "AirPods")])
        await settle { activity.isActive }
        model.stop()                                         // Settings ▸ Live Activities: Bluetooth devices off
        #expect(!activity.isActive)
        model.start()                                        // and on again
        defer { model.stop() }
        hardware.audio?([AudioOutputDevice(id: "1", name: "AirPods"), AudioOutputDevice(id: "2", name: "Beats Flex")])
        await settle { false }
        #expect(!activity.isActive)                          // connected while off: part of the baseline
        hardware.audio?([AudioOutputDevice(id: "2", name: "Beats Flex"), AudioOutputDevice(id: "3", name: "Speaker")])
        await settle { activity.isActive }
        #expect(activity.accessory?.name == "Speaker")       // a new connection after the restart still shows
    }

    @Test func theActivityOnlyAsksForPowerNotificationsWhileVisible() async {
        let model = makeModel()
        model.start()
        defer { model.stop() }
        #expect(!model.wantsPowerSourceChanges)
        hardware.audio?([])
        hardware.audio?([AudioOutputDevice(id: "1", name: "AirPods")])
        await settle { activity.isActive }
        #expect(model.wantsPowerSourceChanges)
        activity.end()
        #expect(!model.wantsPowerSourceChanges)
    }

    @Test func powerNotificationsReadNothingWhileHidden() async {
        let model = makeModel()
        model.powerSourcesChanged()
        await settle { false }
        #expect(hardware.batteryReads == 0)
    }

    @Test func bluetoothWatcherNeedsTheOptionAndAccess() async {
        let model = makeModel()
        model.start()
        defer { model.stop() }
        #expect(!hardware.calls.contains("bluetooth"))
        services.permissions.record(.denied, for: .bluetooth)
        services.settings[SystemSettings.showsAllBluetoothDevices] = true
        await settle { false }
        #expect(!model.isBluetoothWatcherRunning)
        services.permissions.record(.granted, for: .bluetooth)
        await settle { model.isBluetoothWatcherRunning }
        #expect(hardware.calls.contains("bluetooth"))
        services.settings[SystemSettings.showsAllBluetoothDevices] = false
        await settle { !model.isBluetoothWatcherRunning }
        #expect(hardware.calls.last == "no-bluetooth")
    }
}
