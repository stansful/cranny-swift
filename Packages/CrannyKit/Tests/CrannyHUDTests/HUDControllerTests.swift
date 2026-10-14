// The controller with fake hardware: when the tap exists (never without Accessibility, removed when the setting
// goes off), key presses reaching the activity, hiding after the duration, and the environment.
import CrannyCore
import Foundation
import Observation
import Testing
@testable import CrannyHUD

/// An accessibility grant the test can flip (observable, like `PermissionsCenter.statuses`).
@MainActor @Observable final class FakeGrant {
    var granted = true
}

@MainActor @Suite struct HUDControllerTests {
    let environment = PreviewSystemEnvironment()
    let services: CrannyServices
    let fake = FakeHardware()
    let grant = FakeGrant()
    let activity: HUDActivity
    let controller: HUDController

    init() {
        services = CrannyServices.preview(environment: environment)
        activity = HUDActivity(settings: services.settings)
        controller = HUDController(services: services, activity: activity, hardware: fake.hardware,
                                   accessibilityGranted: { [grant] in grant.granted },
                                   feedback: FeedbackSound(isEnabledInSystem: { false }))
    }

    private var settings: SettingsStore { services.settings }

    @Test func offByDefaultNothingRuns() {
        controller.start()
        defer { controller.stop() }
        #expect(fake.taps.isEmpty)
        #expect(fake.observers.isEmpty)
        #expect(!controller.isTapRunning)
    }

    @Test func turningTheSettingOnAndOffAddsAndRemovesTheTap() async throws {
        controller.start()
        defer { controller.stop() }
        settings[HUDSettings.replaceSystemHUD] = true
        #expect(await eventually { fake.taps.count == 1 })
        let tap = try #require(fake.taps.first)
        #expect(tap.startCount == 1)
        #expect(controller.isTapRunning)
        #expect(fake.observers.first?.isRunning == true)
        settings[HUDSettings.replaceSystemHUD] = false
        #expect(await eventually { tap.stopCount == 1 })
        #expect(!controller.isTapRunning)
        #expect(fake.observers.first?.isRunning == false)
    }

    @Test func withoutAccessibilityThereIsNoTap() async {
        grant.granted = false
        settings[HUDSettings.replaceSystemHUD] = true
        controller.start()
        defer { controller.stop() }
        #expect(fake.taps.isEmpty)
        grant.granted = true                                        // granted later in System Settings
        #expect(await eventually { fake.taps.count == 1 })
    }

    @Test func disablingTheActivityHandsTheKeysBack() async {
        settings[HUDSettings.replaceSystemHUD] = true
        settings[CoreSettings.activityPreferences] = [.hud: ActivityPreference(isEnabled: false, peeksOnChange: false)]
        controller.start()
        defer { controller.stop() }
        #expect(fake.taps.isEmpty)
    }

    @Test func noVolumeListenerWhenVolumeIsOff() {
        settings[HUDSettings.replaceSystemHUD] = true
        settings[HUDSettings.volume] = false
        controller.start()
        defer { controller.stop() }
        #expect(fake.taps.count == 1)                               // brightness / keyboard still need the tap
        #expect(fake.observers.isEmpty)
    }

    @Test func aFailedTapIsNotKept() {
        fake.tapStartSucceeds = false
        let controller = HUDController(services: services, activity: activity, hardware: fake.hardware,
                                       accessibilityGranted: { true }, feedback: FeedbackSound(isEnabledInSystem: { false }))
        settings[HUDSettings.replaceSystemHUD] = true
        controller.start()
        defer { controller.stop() }
        #expect(fake.taps.count == 1)
        #expect(!controller.isTapRunning)
    }

    @Test func aKeyPressShowsTheHUDAndItHidesAfterTheDuration() async throws {
        settings[HUDSettings.replaceSystemHUD] = true
        settings[HUDSettings.duration] = 0.8                       // the shortest allowed
        controller.start()
        defer { controller.stop() }
        let tap = try #require(fake.taps.first)
        #expect(tap.handler.handle(MediaKeyEvent(key: .soundUp, isDown: true)))
        #expect(await eventually { activity.isActive })
        #expect(activity.display?.level == 0.5625)
        #expect(activity.revision == 1)
        #expect(activity.priority == .hud)
        let expires = try #require(activity.expiresAt)
        #expect(expires.timeIntervalSinceNow <= 0.8)          // now + duration, minus the hop to the main actor
        #expect(fake.volume.state?.level == 0.5625)
        #expect(await eventually(timeout: .seconds(3)) { !activity.isActive })
        #expect(activity.display != nil)                           // kept for the out-animation
    }

    @Test func passedThroughKeysShowNothing() async throws {
        settings[HUDSettings.replaceSystemHUD] = true
        controller.start()
        defer { controller.stop() }
        let tap = try #require(fake.taps.first)
        #expect(!tap.handler.handle(MediaKeyEvent(key: .soundUp, isDown: true, modifiers: .option)))
        #expect(!tap.handler.handle(MediaKeyEvent(key: .play, isDown: true)))
        try await Task.sleep(for: .milliseconds(50))
        #expect(!activity.isActive)
        #expect(fake.volume.calls.isEmpty)
    }

    @Test func lockingHidesTheHUDAndPassesKeys() async throws {
        settings[HUDSettings.replaceSystemHUD] = true
        controller.start()
        defer { controller.stop() }
        let tap = try #require(fake.taps.first)
        _ = tap.handler.handle(MediaKeyEvent(key: .soundDown, isDown: true))
        #expect(await eventually { activity.isActive })
        environment.isScreenLocked = true
        #expect(await eventually { !activity.isActive })
        #expect(!tap.handler.handle(MediaKeyEvent(key: .soundDown, isDown: true)))   // macOS shows its HUD on the lock screen
        #expect(fake.taps.count == 1)                                // the tap stays for after unlocking
    }

    @Test func voiceOverActionsAdjustTheLevel() async throws {
        settings[HUDSettings.replaceSystemHUD] = true
        controller.start()
        defer { controller.stop() }
        let tap = try #require(fake.taps.first)
        _ = tap.handler.handle(MediaKeyEvent(key: .soundUp, isDown: true))
        #expect(await eventually { activity.isActive })
        #expect(activity.actions.map(\.id) == ["increase", "decrease", "mute"])
        activity.actions.first { $0.id == "decrease" }?.perform()
        #expect(await eventually { activity.display?.level == 0.5 })
        #expect(activity.revision == 2)
    }

    @Test func aVisibleVolumeHUDFollowsTheOutput() async throws {
        settings[HUDSettings.replaceSystemHUD] = true
        controller.start()
        defer { controller.stop() }
        let tap = try #require(fake.taps.first)
        _ = tap.handler.handle(MediaKeyEvent(key: .soundUp, isDown: true))
        #expect(await eventually { activity.isActive })
        let observer = try #require(fake.observers.first)
        observer.emit(VolumeObservation(level: 0.25, isMuted: false,
                                        device: OutputDevice(id: 2, name: "AirPods Max", transport: 0x626C_7565),
                                        deviceChanged: true))
        #expect(await eventually { activity.display?.deviceGlyph == "airpodsmax" })
        #expect(activity.display?.level == 0.25)
        #expect(activity.revision == 1)
    }

    @Test func stopRemovesEverything() async throws {
        settings[HUDSettings.replaceSystemHUD] = true
        controller.start()
        let tap = try #require(fake.taps.first)
        _ = tap.handler.handle(MediaKeyEvent(key: .soundUp, isDown: true))
        #expect(await eventually { activity.isActive })
        controller.stop()
        #expect(tap.stopCount == 1)
        #expect(!activity.isActive)
        #expect(!tap.handler.handle(MediaKeyEvent(key: .soundUp, isDown: true)))
    }
}
