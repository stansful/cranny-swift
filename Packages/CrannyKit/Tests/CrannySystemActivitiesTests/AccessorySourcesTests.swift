// Accessory sources parsed from captured dictionaries: private IOPS accessories, IOKit HID properties,
// Bluetooth class of device. No hardware is touched.
import Foundation
import Testing
@testable import CrannySystemActivities

@Suite struct AccessorySourcesTests {
    private func sources(_ xmls: String...) throws -> [PowerSourceAccessory] {
        AccessoryPowerSources.parse(try xmls.map(Fixtures.dictionary))
    }

    @Test func combinedPartsBecomeLeftAndRight() throws {
        let parsed = try sources(Fixtures.airPodsBuds)
        #expect(parsed.map(\.part) == [.combined, .left, .right])
        #expect(parsed.map(\.level.percent) == [81, 84, 81])
        #expect(parsed.allSatisfy { $0.groupID == "00000000-0000-4000-8000-000000000001" && $0.productID == 0x201B && $0.vendorID == 76 })
    }

    @Test func airPodsGroupIntoOneReportWithTheirCase() throws {
        let reports = AccessoryPowerSources.group(try sources(Fixtures.trackpad, Fixtures.airPodsCase, Fixtures.airPodsBuds))
        #expect(reports.count == 2)
        let trackpad = try #require(reports.first)
        #expect(trackpad.name == "Magic Trackpad")
        #expect(trackpad.kind == .trackpad)
        #expect(trackpad.batteries == AccessoryBatteries(main: BatteryLevel(percent: 64)))
        let airPods = try #require(reports.last)
        #expect(airPods.name == "AirPods")                 // the buds' name, never the case's
        #expect(airPods.category == "Headset")
        #expect(airPods.kind == .earbuds)                  // product 0x201B: AirPods 4
        #expect(airPods.batteries.main?.percent == 81)
        #expect(airPods.batteries.left?.percent == 84)
        #expect(airPods.batteries.right?.percent == 81)
        #expect(airPods.batteries.chargingCase?.percent == 13)
        #expect(airPods.batteries.summary?.percent == 81)
    }

    @Test func sourcesWithoutALevelOrNotPresentAreSkipped() throws {
        var absent = try Fixtures.dictionary(Fixtures.trackpad)
        absent["Is Present"] = NSNumber(value: false)
        var noLevel = try Fixtures.dictionary(Fixtures.trackpad)
        noLevel["Current Capacity"] = nil
        #expect(AccessoryPowerSources.parse([absent, noLevel]).isEmpty)
    }

    @Test func batterySummaryPrefersCombinedThenTheEmptierBud() {
        #expect(AccessoryBatteries(main: BatteryLevel(percent: 50), left: BatteryLevel(percent: 10)).summary?.percent == 50)
        #expect(AccessoryBatteries(left: BatteryLevel(percent: 70), right: BatteryLevel(percent: 40)).summary?.percent == 40)
        #expect(AccessoryBatteries(right: BatteryLevel(percent: 40)).summary?.percent == 40)
        #expect(AccessoryBatteries(chargingCase: BatteryLevel(percent: 90)).summary == nil)      // the case never counts
        #expect(AccessoryBatteries.unknown.isEmpty)
        #expect(BatteryLevel(percent: 140).percent == 100)
    }

    // MARK: HID

    @Test func hidKeepsBluetoothAccessoriesOnly() throws {
        let trackpad = try #require(HIDPeripheral.parse(try Fixtures.dictionary(Fixtures.hidTrackpad), id: 7))
        #expect(trackpad.name == "Magic Trackpad Office")  // whitespace collapsed
        #expect(trackpad.category == "Trackpad")
        #expect(trackpad.vendorID == 76 && trackpad.productID == 804)
        #expect(trackpad.batteryPercent == 64)
        #expect(HIDPeripheral.parse(try Fixtures.dictionary(Fixtures.hidBuiltIn), id: 1) == nil)
        var usb = try Fixtures.dictionary(Fixtures.hidTrackpad)
        usb["Transport"] = "USB"
        #expect(HIDPeripheral.parse(usb, id: 8) == nil)    // a cable connection is not a Bluetooth connection
    }

    // MARK: IOBluetooth class of device

    @Test func classOfDeviceMapsToKinds() {
        #expect(BluetoothDeviceInfo.kind(major: 0x04, minor: 0x06) == .headphones)
        #expect(BluetoothDeviceInfo.kind(major: 0x04, minor: 0x01) == .headphones)
        #expect(BluetoothDeviceInfo.kind(major: 0x04, minor: 0x05) == .speaker)
        #expect(BluetoothDeviceInfo.kind(major: 0x05, minor: 0x10) == .keyboard)
        #expect(BluetoothDeviceInfo.kind(major: 0x05, minor: 0x20) == .mouse)
        #expect(BluetoothDeviceInfo.kind(major: 0x05, minor: 0x30) == .keyboard)
        #expect(BluetoothDeviceInfo.kind(major: 0x05, minor: 0x02) == .gameController)
        #expect(BluetoothDeviceInfo.kind(major: 0x01, minor: 0x00) == .other)
    }
}
