// What the power observer follows (energy): every change only while the details matter, the AC ↔ battery switch
// always; and a restart (Settings ▸ Live Activities) that starts from a baseline like launch. Fake observer and
// injected reads: no IOKit.
import CrannyCore
import Foundation
import Observation
import os
import Testing
@testable import CrannySystemActivities

/// Records what the model asks the observer to follow, and fires notifications by hand.
@MainActor final class FakePowerObserver: PowerChangeObserving {
    private(set) var isRunning = false
    private(set) var followsDetail = false
    private(set) var detailChanges: [Bool] = []
    private var onChange: (@MainActor () -> Void)?

    func start(_ onChange: @escaping @MainActor () -> Void) {
        self.onChange = onChange
        isRunning = true
        followsDetail = true                       // like `PowerObserver.start`
    }
    func setFollowsDetail(_ on: Bool) {
        guard isRunning else { return }
        followsDetail = on
        detailChanges.append(on)
    }
    func stop() {
        onChange = nil
        isRunning = false
        followsDetail = false
    }
    /// A notification (the switch while not following details; any change while following).
    func fire() { onChange?() }
}

/// The battery the injected read reports, and how often it was read.
nonisolated final class FakeBattery: Sendable {
    private let store: OSAllocatedUnfairLock<(state: BatteryState, reads: Int)>
    init(_ state: BatteryState) { store = OSAllocatedUnfairLock(initialState: (state, 0)) }
    var reads: Int { store.withLock { $0.reads } }
    func set(_ state: BatteryState) { store.withLock { $0.state = state } }
    var read: @concurrent @Sendable () async -> BatteryState {
        { [store] in store.withLock { $0.reads += 1; return $0.state } }
    }
}

/// Something on screen that shows accessory batteries (the accessory model's `wantsPowerSourceChanges`).
@MainActor @Observable final class VisibleFlag { var isOn = false }

@MainActor @Suite struct PowerDetailTests {
    let services = CrannyServices.preview()
    let charging = ChargingActivity()
    let lowBattery = LowBatteryActivity(openBatterySettings: {})
    let observer = FakePowerObserver()

    private func model(_ battery: FakeBattery) -> PowerModel {
        PowerModel(settings: services.settings, charging: charging, lowBattery: lowBattery, read: battery.read,
                   observer: observer)
    }
    private func onBattery(_ percent: Int) -> BatteryState { BatteryState(hasBattery: true, percent: percent, isPluggedIn: false) }
    private func onPower(_ percent: Int) -> BatteryState {
        BatteryState(hasBattery: true, percent: percent, isPluggedIn: true, isCharging: true)
    }

    /// Polls until `condition` holds (generous: other suites share the main actor; it returns as soon as it holds).
    private func settle(_ condition: () -> Bool) async -> Bool {
        let start = Date()
        while !condition() && Date().timeIntervalSince(start) < 10 { try? await Task.sleep(for: .milliseconds(10)) }
        return condition()
    }

    @Test func onPowerWithNothingShownOnlyTheSwitchIsFollowed() async {
        let battery = FakeBattery(onPower(80))
        let model = model(battery)
        model.start()
        defer { model.stop() }
        #expect(observer.followsDetail)                                     // until the first read says otherwise
        #expect(await settle { model.state != nil && !observer.followsDetail })
        #expect(!model.followsDetail)
        #expect(!charging.isActive && !lowBattery.isActive)                 // launch is a baseline
    }

    @Test func unpluggingFollowsEveryChangeAgainAndReadsOnceMore() async {
        services.settings[CoreSettings.peekDuration] = 1                   // the minimum
        let battery = FakeBattery(onPower(80))
        let model = model(battery)
        model.start()
        defer { model.stop() }
        #expect(await settle { model.state != nil && !observer.followsDetail })
        let reads = battery.reads
        battery.set(onBattery(80))
        observer.fire()                                                      // the limited-power notification
        #expect(await settle { observer.followsDetail && battery.reads >= reads + 2 })   // the switch, then the re-read
        #expect(charging.isActive)                                           // the unplug peek, as before
        // On battery the thresholds need every percent: it keeps following after the peek.
        #expect(await settle { !charging.isActive })
        #expect(observer.followsDetail)
        battery.set(onBattery(20))
        observer.fire()
        #expect(await settle { lowBattery.isActive })                       // the first warning still arrives
    }

    @Test func aVisibleActivityKeepsFollowingOnPower() async {
        services.settings[CoreSettings.peekDuration] = 1
        let battery = FakeBattery(onBattery(60))
        let model = model(battery)
        model.start()
        defer { model.stop() }
        #expect(await settle { model.state != nil })
        battery.set(onPower(60))
        observer.fire()
        #expect(await settle { charging.isActive })
        #expect(observer.followsDetail)                                     // the peek shows percent and minutes
        #expect(await settle { !charging.isActive && !observer.followsDetail })   // gone: only the switch
    }

    @Test func visibleAccessoryBatteriesKeepFollowingOnPower() async {
        let battery = FakeBattery(onPower(90))
        let shown = VisibleFlag()
        let model = model(battery)
        model.wantsSourcesChanged = { shown.isOn }
        model.start()
        defer { model.stop() }
        #expect(await settle { model.state != nil && !observer.followsDetail })
        shown.isOn = true                                                    // a Bluetooth device appears
        #expect(await settle { observer.followsDetail })
        shown.isOn = false
        #expect(await settle { !observer.followsDetail })
    }

    @Test func aMacWithoutABatteryKeepsFollowing() async {
        let battery = FakeBattery(.noBattery())                              // or one IOKit has not found yet
        let model = model(battery)
        model.start()
        defer { model.stop() }
        #expect(await settle { model.state != nil })
        try? await Task.sleep(for: .milliseconds(50))
        #expect(observer.followsDetail)
        #expect(observer.detailChanges.isEmpty)
    }

    @Test func aRestartStartsFromABaseline() async {
        let battery = FakeBattery(onBattery(50))
        let model = model(battery)
        model.start()
        #expect(await settle { model.state?.isPluggedIn == false })
        model.stop()                                                         // Settings ▸ Live Activities: off
        #expect(!observer.isRunning)
        battery.set(onPower(50))                                             // plugged in meanwhile
        model.start()                                                        // and on again
        defer { model.stop() }
        #expect(await settle { model.state?.isPluggedIn == true })
        #expect(!charging.isActive)                                          // no peek for what happened while off
        #expect(model.followsDetail == observer.followsDetail)
    }

    @Test func stoppingHidesTheActivities() {
        let model = model(FakeBattery(onBattery(5)))
        model.apply(onBattery(6))
        model.apply(onBattery(5))
        #expect(lowBattery.isPersistent)
        model.stop()
        #expect(!lowBattery.isActive && !charging.isActive)
    }
}
