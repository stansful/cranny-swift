// Matching sources into the accessory the Bluetooth activity shows, and deciding what is a NEW connection.
import AppKit
import Foundation
import Testing
@testable import CrannySystemActivities

@Suite struct AccessoryCatalogTests {
    private func reports() throws -> [AccessoryBatteryReport] {
        AccessoryPowerSources.group(AccessoryPowerSources.parse(
            try [Fixtures.trackpad, Fixtures.airPodsCase, Fixtures.airPodsBuds].map(Fixtures.dictionary)))
    }

    @Test func namesMatchAcrossSources() {
        #expect(AccessoryCatalog.normalizedName("AirPods Pro 🅛") == "airpods pro")
        #expect(AccessoryCatalog.normalizedName("  Magic  Trackpad ") == "magic trackpad")
        #expect(AccessoryCatalog.normalizedName("Stan’s AirPods") == AccessoryCatalog.normalizedName("stan's airpods"))
        #expect(AccessoryCatalog.normalizedName("Наушники Ёлки") == "наушники елки")
        #expect(AccessoryCatalog.normalizedName("🅛").isEmpty)
    }

    @Test func headphonesFromCoreAudioTakeBatteriesByName() throws {
        let accessory = AccessoryCatalog.accessory(audio: AudioOutputDevice(id: "uid-1", name: "AirPods"), reports: try reports())
        #expect(accessory.id == "audio:uid-1")
        #expect(accessory.kind == .earbuds)
        #expect(accessory.symbol == "airpods.gen3")
        #expect(accessory.batteries.left?.percent == 84)
        #expect(accessory.batteries.chargingCase?.percent == 13)
    }

    @Test func unknownHeadphonesShowWithoutLevels() throws {
        let accessory = AccessoryCatalog.accessory(audio: AudioOutputDevice(id: "uid-2", name: "Studio Cans"), reports: try reports())
        #expect(accessory.kind == .headphones)
        #expect(accessory.symbol == "headphones")
        #expect(accessory.batteries.isEmpty)
    }

    @Test func magicAccessoriesMatchByProductEvenWithAnotherName() throws {
        let peripheral = HIDPeripheral(id: 9, name: "Trackpad Office", category: "Trackpad", vendorID: 76, productID: 804, batteryPercent: 63)
        let accessory = AccessoryCatalog.accessory(hid: peripheral, reports: try reports())
        #expect(accessory.id == "hid:9")
        #expect(accessory.kind == .trackpad)
        #expect(accessory.symbol == "rectangle.and.hand.point.up.left.filled")
        #expect(accessory.batteries.main?.percent == 64)     // IOPS wins over the registry's own value
    }

    @Test func hidBatteryIsTheFallback() {
        let mouse = HIDPeripheral(id: 3, name: "Magic Mouse", category: "Mouse", vendorID: 76, productID: 0x0269, batteryPercent: 55)
        let accessory = AccessoryCatalog.accessory(hid: mouse, reports: [])
        #expect(accessory.batteries.main?.percent == 55)
        #expect(accessory.symbol == "magicmouse")
    }

    @Test func bluetoothDevicesUseTheirOwnLevelsWhenIOPSHasNone() {
        let device = BluetoothDeviceInfo(id: "aa", name: "Desk Speaker", kind: .speaker,
                                         batteries: AccessoryBatteries(main: BatteryLevel(percent: 30)))
        let accessory = AccessoryCatalog.accessory(bluetooth: device, reports: [])
        #expect(accessory.id == "bluetooth:aa")
        #expect(accessory.symbol == "hifispeaker")
        #expect(accessory.batteries.main?.percent == 30)
    }

    @Test func refreshKeepsIdentityAndUpdatesLevels() throws {
        let shown = AccessoryCatalog.accessory(audio: AudioOutputDevice(id: "uid-1", name: "AirPods"), reports: [])
        #expect(shown.batteries.isEmpty)                      // the connection came before the levels
        let refreshed = AccessoryCatalog.refreshed(shown, reports: try reports(), hid: [], bluetooth: [])
        #expect(refreshed.id == shown.id && refreshed.name == shown.name)
        #expect(refreshed.batteries.right?.percent == 81)
        #expect(refreshed.productID == 0x201B)

        let peripheral = HIDPeripheral(id: 4, name: "Keys", category: "Keyboard", vendorID: 1, productID: 2, batteryPercent: 90)
        let keyboard = AccessoryCatalog.accessory(hid: peripheral, reports: [])
        var drained = peripheral
        drained.batteryPercent = 89
        #expect(AccessoryCatalog.refreshed(keyboard, reports: [], hid: [drained], bluetooth: []).batteries.main?.percent == 89)
    }

    @Test func identicalProductsAreMatchedByNameInstead() throws {
        var second = try #require(try reports().first)
        second.name = "Magic Trackpad 2"
        let both = try reports() + [second]
        #expect(AccessoryCatalog.report(vendorID: 76, productID: 804, in: both) == nil)
    }

    // MARK: Tracker

    @Test func firstReportOfEachSourceIsTheBaseline() {
        var tracker = AccessoryTracker()
        var steps: [Set<String>] = []
        steps.append(tracker.newIDs(["a", "b"], from: .audio))
        steps.append(tracker.newIDs(["a", "b", "c"], from: .audio))
        steps.append(tracker.newIDs(["c"], from: .audio))
        steps.append(tracker.newIDs(["a", "c"], from: .audio))          // reconnect
        steps.append(tracker.newIDs(["x"], from: .hid))                 // another source: its own baseline
        tracker.forget(.hid)
        steps.append(tracker.newIDs(["x", "y"], from: .hid))
        #expect(steps == [[], ["c"], [], ["a"], [], []])
    }

    @Test func oneDeviceSeenTwiceIsAnnouncedOnce() {
        var tracker = AccessoryTracker()
        let now = Date()
        let answers = [tracker.shouldAnnounce(name: "AirPods", at: now),
                       tracker.shouldAnnounce(name: "airpods ", at: now.addingTimeInterval(1)),
                       tracker.shouldAnnounce(name: "Magic Trackpad", at: now.addingTimeInterval(1)),
                       tracker.shouldAnnounce(name: "AirPods", at: now.addingTimeInterval(AccessoryTracker.duplicateWindow + 1))]
        #expect(answers == [true, false, true, true])
    }

    // MARK: Symbols

    @Test @MainActor func everyGlyphExistsOnThisSystem() {
        for symbol in DeviceSymbols.allSymbols.union(["bolt.fill", "powerplug.fill", "battery.25percent", "battery.0percent",
                                                      "exclamationmark", "checkmark.circle.fill",
                                                      "exclamationmark.triangle.fill"]) {
            #expect(NSImage(systemSymbolName: symbol, accessibilityDescription: nil) != nil, "missing \(symbol)")
        }
    }

    @Test func restrictedGlyphsOnlyForTheirProducts() {
        let restricted = ["airpods", "airpods.gen3", "beats.headphones", "magicmouse"]
        for kind in AccessoryKind.allCases {
            #expect(!restricted.contains(DeviceSymbols.symbol(for: kind, isApple: false)))
        }
        #expect(DeviceSymbols.symbol(vendorID: 76, productID: 0x2014, kind: .earbuds) == "airpodspro")
        #expect(DeviceSymbols.symbol(vendorID: 76, productID: 0x200A, kind: .headphones) == "airpodsmax")
        #expect(DeviceSymbols.symbol(vendorID: 999, productID: 0x2014, kind: .earbuds) == "earbuds")   // not Apple
        #expect(DeviceSymbols.symbol(vendorID: 76, productID: 0x7FFF, kind: .headphones) == "headphones")
        #expect(DeviceSymbols.symbol(vendorID: 76, productID: nil, kind: .mouse) == "magicmouse")
        #expect(DeviceSymbols.symbol(vendorID: nil, productID: nil, kind: .mouse) == "computermouse")
    }

    @Test func categoriesMapToKinds() {
        #expect(DeviceSymbols.kind(forCategory: "Headset") == .headphones)
        #expect(DeviceSymbols.kind(forCategory: "Audio Battery Case") == nil)
        #expect(DeviceSymbols.kind(forCategory: "Trackpad") == .trackpad)
        #expect(DeviceSymbols.kind(forCategory: "Keyboard") == .keyboard)
        #expect(DeviceSymbols.kind(forCategory: "Mouse") == .mouse)
        #expect(DeviceSymbols.kind(forCategory: "Game Controller") == .gameController)
        #expect(DeviceSymbols.kind(forCategory: nil) == nil)
    }
}
