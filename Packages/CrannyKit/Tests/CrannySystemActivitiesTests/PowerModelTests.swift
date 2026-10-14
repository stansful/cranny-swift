// Snapshots → Charging and Low battery activities (no IOKit: `apply` is fed directly, `read` is injected).
import CrannyCore
import Foundation
import Testing
@testable import CrannySystemActivities

@MainActor @Suite struct PowerModelTests {
    let services = CrannyServices.preview()
    let charging = ChargingActivity()
    let lowBattery = LowBatteryActivity(openBatterySettings: {})

    private func model(read: @escaping @Sendable () async -> BatteryState = { .noBattery() }) -> PowerModel {
        PowerModel(settings: services.settings, charging: charging, lowBattery: lowBattery, read: read, observer: nil)
    }
    private func onBattery(_ percent: Int, minutes: Int? = nil) -> BatteryState {
        BatteryState(hasBattery: true, percent: percent, isPluggedIn: false, minutesToEmpty: minutes)
    }
    private func onPower(_ percent: Int, charging: Bool = true, minutes: Int? = nil) -> BatteryState {
        BatteryState(hasBattery: true, percent: percent, isPluggedIn: true, isCharging: charging, minutesToFull: minutes)
    }

    @Test func plugInShowsOneTransientChargingActivityWithTheSweep() {
        let model = model()
        let now = Date(timeIntervalSinceReferenceDate: 1_000)
        model.apply(onBattery(50), now: now)
        #expect(!charging.isActive)
        model.apply(onPower(50, minutes: 95), now: now)
        #expect(charging.isActive)
        #expect(charging.revision == 1)
        #expect(charging.content == ChargingContent(phase: .charging, percent: 50, minutes: 95))
        #expect(charging.expiresAt == now.addingTimeInterval(HoverIntent.peekAutoDismiss))       // 2.6 s by default
        #expect(charging.delight == .chargeSweep)
        #expect(charging.palette == .charging)
        #expect(charging.priority == .alert)
        // A later snapshot (estimate arrives) updates the content without a new revision.
        model.apply(onPower(51, minutes: 90), now: now)
        #expect(charging.revision == 1)
        #expect(charging.content?.percent == 51)
    }

    @Test func unplugIsANewRevisionWithoutSweepOrLight() {
        let model = model()
        model.apply(onPower(80))
        model.apply(onBattery(80, minutes: 300))
        #expect(charging.revision == 1)
        #expect(charging.content?.phase == .onBattery)
        #expect(charging.delight == nil)
        #expect(charging.palette == nil)
    }

    @Test func noActivityAtLaunch() {
        let model = model()
        model.apply(onPower(100, charging: false))
        #expect(!charging.isActive && !lowBattery.isActive)
    }

    @Test func transientDurationFollowsThePeekDurationSetting() {
        services.settings[CoreSettings.peekDuration] = 5
        let model = model()
        let now = Date()
        model.apply(onBattery(40), now: now)
        model.apply(onPower(40), now: now)
        #expect(charging.expiresAt == now.addingTimeInterval(5))
    }

    @Test func transientActivitiesEndOnTheirOwn() async throws {
        services.settings[CoreSettings.peekDuration] = 1                   // the minimum
        let model = model()
        model.apply(onBattery(40))
        let start = Date()
        model.apply(onPower(40))
        #expect(charging.isActive)
        // One sleep to the deadline ends it. Poll generously: other tests share the main actor.
        while charging.isActive && Date().timeIntervalSince(start) < 10 {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(!charging.isActive)
        #expect(charging.expiresAt == nil)
        #expect(Date().timeIntervalSince(start) >= 0.95)
    }

    @Test func firstWarningIsTransientFinalWarningStays() {
        let model = model()
        model.apply(onBattery(21))
        model.apply(onBattery(20, minutes: 70))
        #expect(lowBattery.isActive)
        #expect(lowBattery.revision == 1)
        #expect(!lowBattery.isPersistent)
        #expect(lowBattery.content?.level == .warning)
        model.apply(onBattery(10, minutes: 30))
        #expect(lowBattery.revision == 2)
        #expect(lowBattery.isPersistent)
        #expect(lowBattery.content == LowBatteryContent(level: .critical, percent: 10, minutesToEmpty: 30))
        model.apply(onBattery(9, minutes: 26))                              // new numbers, same alert
        #expect(lowBattery.revision == 2)
        #expect(lowBattery.content?.percent == 9)
    }

    @Test func connectingPowerEndsTheLowBatteryActivity() {
        let model = model()
        model.apply(onBattery(11))
        model.apply(onBattery(10))
        #expect(lowBattery.isPersistent)
        model.apply(onPower(10))
        #expect(!lowBattery.isActive)
        #expect(charging.isActive)
    }

    @Test func launchingBelowTheFinalWarningShowsItWithoutAPeek() {
        let model = model()
        model.apply(onBattery(7))
        #expect(lowBattery.isActive)
        #expect(lowBattery.isPersistent)
        #expect(lowBattery.revision == 0)                                   // the shell peeks only on revision changes
    }

    @Test func thresholdsComeFromSettings() async {
        services.settings[SystemSettings.lowBatteryThresholds] = [30, 5]
        let model = model()
        model.apply(onBattery(31))
        model.apply(onBattery(30))
        #expect(lowBattery.content?.level == .warning)
        model.apply(onBattery(10))
        #expect(lowBattery.content?.level == .warning)                      // 10 % is no longer a threshold
        model.apply(onBattery(5))
        #expect(lowBattery.isPersistent)
    }

    @Test func raisingTheFinalWarningShowsItRightAway() async {
        let model = model(read: { BatteryState(hasBattery: true, percent: 14, isPluggedIn: false) })
        model.start()
        defer { model.stop() }
        for _ in 0..<100 where model.state == nil { await Task.yield() }
        #expect(model.state?.percent == 14)
        #expect(!lowBattery.isActive)
        services.settings[SystemSettings.lowBatteryThresholds] = [20, 15]
        for _ in 0..<50 where !lowBattery.isActive { await Task.yield() }
        #expect(lowBattery.isPersistent)
        #expect(lowBattery.revision == 0)
    }

    @Test func desktopMacsShowNothing() {
        let model = model()
        model.apply(.noBattery())
        model.apply(.noBattery(isPluggedIn: false))
        #expect(!charging.isActive && !lowBattery.isActive)
    }

    @Test func refreshReadsOffTheMainActorAndApplies() async {
        let model = model(read: { BatteryState(hasBattery: true, percent: 42, isPluggedIn: false) })
        model.refresh()
        for _ in 0..<100 where model.state == nil { await Task.yield() }
        #expect(model.state?.percent == 42)
    }
}
