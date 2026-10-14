// BatteryState parsing from captured IOPS dictionaries (ARCHITECTURE.md §10.11 acceptance: charging,
// discharging, plugged-not-charging, desktop).
import Foundation
import IOKit.ps
import Testing
@testable import CrannySystemActivities

@Suite struct BatteryStateTests {
    private func parse(_ xml: String, providing: String?, adapter: Bool = false, lowPower: Bool = false) throws -> BatteryState {
        BatteryState.parse(sources: [try Fixtures.dictionary(xml)], providingType: providing,
                           adapter: adapter ? try Fixtures.dictionary(Fixtures.adapter) : nil, isLowPowerMode: lowPower)
    }

    @Test func pluggedInNotChargingIsTheThirdState() throws {
        let state = try parse(Fixtures.pluggedInNotCharging, providing: kIOPSACPowerValue, adapter: true)
        #expect(state.hasBattery)
        #expect(state.percent == 80)
        #expect(state.isPluggedIn)
        #expect(!state.isCharging)
        #expect(state.charge == .pluggedInNotCharging)
        #expect(state.minutesToEmpty == nil)          // IOPS says 0 on power: no estimate
        #expect(state.minutesToFull == nil)
        #expect(state.adapterWatts == 140)
        #expect(ChargingContent(state).phase == .notCharging)
    }

    @Test func charging() throws {
        let state = try parse(Fixtures.charging, providing: kIOPSACPowerValue)
        #expect(state.charge == .charging)
        #expect(state.percent == 46)
        #expect(state.minutesToFull == 80)
        #expect(state.minutesToEmpty == nil)
        #expect(ChargingContent(state) == ChargingContent(phase: .charging, percent: 46, minutes: 80))
    }

    @Test func chargingWhileEstimating() throws {
        let state = try parse(Fixtures.chargingEstimating, providing: kIOPSACPowerValue)
        #expect(state.charge == .charging)
        #expect(state.minutesToFull == nil)            // -1 = still calculating
    }

    @Test func fullOnPower() throws {
        let state = try parse(Fixtures.full, providing: kIOPSACPowerValue)
        #expect(state.isCharged)
        #expect(state.charge == .pluggedInNotCharging)
        #expect(ChargingContent(state).phase == .charged)
    }

    @Test func discharging() throws {
        let state = try parse(Fixtures.discharging, providing: kIOPSBatteryPowerValue)
        #expect(state.charge == .discharging)
        #expect(!state.isPluggedIn)
        #expect(state.percent == 64)
        #expect(state.minutesToEmpty == 250)
        #expect(state.minutesToFull == nil)
        #expect(ChargingContent(state) == ChargingContent(phase: .onBattery, percent: 64, minutes: 250))
    }

    @Test func dischargingWhileEstimating() throws {
        let state = try parse(Fixtures.dischargingEstimating, providing: kIOPSBatteryPowerValue)
        #expect(state.minutesToEmpty == nil)
    }

    @Test func lowPowerModeFromEitherSource() throws {
        #expect(try parse(Fixtures.dischargingLowPower, providing: kIOPSBatteryPowerValue).isLowPowerMode)   // "LPM Active"
        #expect(try parse(Fixtures.discharging, providing: kIOPSBatteryPowerValue, lowPower: true).isLowPowerMode)
        #expect(try !parse(Fixtures.discharging, providing: kIOPSBatteryPowerValue).isLowPowerMode)
    }

    @Test func desktopMacHasNoBattery() {
        let state = BatteryState.parse(sources: [], providingType: kIOPSACPowerValue, adapter: nil, isLowPowerMode: false)
        #expect(!state.hasBattery)
        #expect(state.isPluggedIn)
    }

    @Test func accessoriesAndAbsentBatteriesAreNotTheInternalBattery() throws {
        var absent = try Fixtures.dictionary(Fixtures.discharging)
        absent[kIOPSIsPresentKey] = NSNumber(value: false)
        let state = BatteryState.parse(sources: [try Fixtures.dictionary(Fixtures.trackpad), absent],
                                       providingType: kIOPSACPowerValue, adapter: nil, isLowPowerMode: false)
        #expect(!state.hasBattery)
    }

    @Test func capacityInMilliampHoursBecomesPercent() throws {
        var source = try Fixtures.dictionary(Fixtures.discharging)
        source[kIOPSCurrentCapacityKey] = NSNumber(value: 4321)
        source[kIOPSMaxCapacityKey] = NSNumber(value: 5000)
        let state = BatteryState.parse(sources: [source], providingType: kIOPSBatteryPowerValue, adapter: nil, isLowPowerMode: false)
        #expect(state.percent == 86)
    }

    @Test func missingProvidingTypeFallsBackToTheBatteryState() throws {
        #expect(try parse(Fixtures.charging, providing: nil).isPluggedIn)
        #expect(try !parse(Fixtures.discharging, providing: nil).isPluggedIn)
    }

    @Test func swiftValuesParseLikeCFValues() {
        let source: [String: Any] = [kIOPSTypeKey: kIOPSInternalBatteryType, kIOPSCurrentCapacityKey: 30,
                                     kIOPSMaxCapacityKey: 100, kIOPSIsChargingKey: true]
        let state = BatteryState.parse(sources: [source], providingType: kIOPSACPowerValue, adapter: nil, isLowPowerMode: false)
        #expect(state.percent == 30)
        #expect(state.isCharging)
    }
}
