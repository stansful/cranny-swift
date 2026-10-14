// The controller with fake hardware: when the tap exists (never without Accessibility, removed when the setting
// goes off), key presses reaching the activity, hiding after the duration, and the environment.
import CrannyCore
import Foundation
import Observation
import Testing
@testable import CrannyHUD

/// An accessibility grant the test can flip. `granted` is the cached status (observable, like
/// `PermissionsCenter.statuses`); `trusted` is what macOS says right now (`AXIsProcessTrusted`), which only
/// reaches the cache through `refresh`.
@MainActor @Observable final class FakeGrant {
    var granted = true
    var trusted = true
    private(set) var refreshes = 0

    /// Granted (or revoked) in System Settings: macOS knows, the cache does not yet.
    func changeInSystemSettings(_ trusted: Bool) { self.trusted = trusted }

    var accessibility: HUDAccessibility {
        HUDAccessibility(isGranted: { [self] in granted }, isTrustedNow: { [self] in trusted },
                         refresh: { [self] in refreshes += 1; granted = trusted })
    }
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
                                   accessibility: grant.accessibility,
                                   feedback: FeedbackSound(isEnabledInSystem: { false }))
    }

    private var settings: SettingsStore { services.settings }

    @Test func offByDefaultNothingRuns() {
        controller.start()
        defer { controller.stop() }
        #expect(fake.taps.isEmpty)
        #expect(fake.observers.isEmpty)
        #expect(!controller.isTapRunning)
        #expect(!controller.tapFailed)
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

    @Test func aNewGrantTurnsTheHUDOn() async {
        grant.granted = false                                       // onboarding: the user taps "Allow" …
        controller.start()
        defer { controller.stop() }
        #expect(!settings[HUDSettings.replaceSystemHUD])
        grant.granted = true                                        // … and grants Accessibility
        #expect(await eventually { settings[HUDSettings.replaceSystemHUD] && fake.taps.count == 1 })
    }

    @Test func aNewGrantDoesNotUndoAnExplicitOff() async throws {
        HUDSettingsPane.userSetReplacing(true, settings: settings)
        HUDSettingsPane.userSetReplacing(false, settings: settings)    // the user turned the HUD off …
        grant.granted = false                                         // … a TCC reset dropped the grant …
        controller.start()
        defer { controller.stop() }
        grant.granted = true                                          // … and it is granted again
        try await Task.sleep(for: .milliseconds(100))
        #expect(!settings[HUDSettings.replaceSystemHUD])
        #expect(fake.taps.isEmpty)
        HUDSettingsPane.userSetReplacing(true, settings: settings)     // switching it on clears the memory
        #expect(settings.isDefault(HUDSettings.turnedOffByUser))
        #expect(await eventually { fake.taps.count == 1 })
    }

    @Test func comingBackPicksUpAGrantFromSystemSettings() async {
        grant.granted = false
        grant.trusted = false
        settings[HUDSettings.replaceSystemHUD] = true
        controller.start()
        defer { controller.stop() }
        controller.checkAccessibility()                              // nothing changed: no refresh
        #expect(grant.refreshes == 0)
        grant.changeInSystemSettings(true)
        controller.checkAccessibility()                              // Cranny became active again
        #expect(grant.refreshes == 1)
        #expect(await eventually { fake.taps.count == 1 && controller.isTapRunning })
    }

    @Test func comingBackWithTheToggleOffStillRefreshes() {
        grant.granted = false
        grant.trusted = false
        controller.start()
        defer { controller.stop() }
        grant.changeInSystemSettings(true)                           // "Open System Settings" with the toggle off
        controller.checkAccessibility()
        #expect(grant.granted)                                       // the pane's pill follows
    }

    @Test func aRevokedGrantRemovesTheTapOnReturn() async throws {
        settings[HUDSettings.replaceSystemHUD] = true
        controller.start()
        defer { controller.stop() }
        let tap = try #require(fake.taps.first)
        #expect(controller.isTapRunning)
        grant.changeInSystemSettings(false)                          // revoked while the HUD runs
        controller.checkAccessibility()
        #expect(await eventually { tap.stopCount == 1 && !controller.isTapRunning })
    }

    @Test func aDisabledTapRechecksTheGrant() async throws {
        settings[HUDSettings.replaceSystemHUD] = true
        controller.start()
        defer { controller.stop() }
        let tap = try #require(fake.taps.first)
        grant.changeInSystemSettings(false)
        tap.handler.tapWasDisabled()                                 // what the tap thread reports
        #expect(await eventually { tap.stopCount == 1 && !controller.isTapRunning })
        #expect(grant.refreshes == 1)
    }

    @Test func aGrantFromAnEarlierSessionChangesNothing() async throws {
        controller.start()                                          // granted at launch, HUD off by choice
        defer { controller.stop() }
        try await Task.sleep(for: .milliseconds(50))
        #expect(!settings[HUDSettings.replaceSystemHUD])
        #expect(fake.taps.isEmpty)
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
        settings[HUDSettings.keyboardBacklight] = true
        controller.start()
        defer { controller.stop() }
        #expect(fake.taps.count == 1)                               // brightness / keyboard still need the tap
        #expect(fake.observers.isEmpty)
    }

    @Test func aFailedTapIsNotKept() {
        fake.tapStartSucceeds = false
        let controller = HUDController(services: services, activity: activity, hardware: fake.hardware,
                                       accessibility: grant.accessibility, feedback: FeedbackSound(isEnabledInSystem: { false }))
        settings[HUDSettings.replaceSystemHUD] = true
        controller.start()
        defer { controller.stop() }
        #expect(fake.taps.count == 1)
        #expect(!controller.isTapRunning)
        #expect(controller.tapFailed)                              // Settings ▸ HUD says macOS refused
    }

    @Test func aKeyPressShowsTheHUDAndItHidesAfterTheDuration() async throws {
        settings[HUDSettings.replaceSystemHUD] = true
        settings[HUDSettings.duration] = 0.8                       // the shortest allowed
        controller.start()
        defer { controller.stop() }
        let tap = try #require(fake.taps.first)
        #expect(tap.handler.handle(MediaKeyEvent(key: .soundUp, isDown: true)))
        #expect(await eventually { activity.revision == 1 })       // (it may already have hidden on a busy main actor)
        #expect(activity.display?.level == 0.5625)
        #expect(activity.priority == .hud)
        #expect(activity.expiresAt == nil)                         // the hide sleep is the one deadline: no shell wake-up per press
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
        controller.now = { [start = Date()] in start }              // frozen: the HUD stays up however busy the main actor is
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

    @Test func theTapReceivesNothingWhileTheHUDCannotShow() async throws {
        settings[HUDSettings.replaceSystemHUD] = true
        controller.start()
        defer { controller.stop() }
        let tap = try #require(fake.taps.first)
        #expect(tap.isEnabled && tap.enabledCalls.isEmpty)
        environment.isScreenLocked = true                           // every key would go back to macOS
        #expect(await eventually { !tap.isEnabled })
        #expect(fake.taps.count == 1 && tap.stopCount == 0)          // installed for after unlocking
        environment.isScreenLocked = false
        #expect(await eventually { tap.isEnabled })
        environment.canPresentHUD = false                           // General ▸ Displays ▸ HUD off on the pointer's display
        #expect(await eventually { !tap.isEnabled })
        #expect(tap.enabledCalls == [false, true, false])           // one call per change
    }

    @Test func aTapCreatedWhileTheHUDCannotShowStartsOff() throws {
        environment.isScreenLocked = true
        settings[HUDSettings.replaceSystemHUD] = true
        controller.start()
        defer { controller.stop() }
        let tap = try #require(fake.taps.first)
        #expect(tap.enabledCalls == [false])
    }

    @Test func aGrantRevokedWhileTheTapWasOffIsNoticedOnTheWayBack() async throws {
        settings[HUDSettings.replaceSystemHUD] = true
        controller.start()
        defer { controller.stop() }
        let tap = try #require(fake.taps.first)
        environment.canPresentHUD = false
        #expect(await eventually { !tap.isEnabled })
        grant.changeInSystemSettings(false)                         // revoked meanwhile: no tap event can say so
        environment.canPresentHUD = true
        #expect(await eventually { tap.stopCount == 1 && !controller.isTapRunning })
        #expect(grant.refreshes == 1)
    }

    @Test func theConfigReadsWhetherTheShellWouldDrawTheHUD() {
        #expect(controller.configInputs().shellCanPresentHUD)
        environment.canPresentHUD = false                           // General ▸ Displays ▸ HUD off on the pointer's display
        #expect(!controller.configInputs().shellCanPresentHUD)
    }

    @Test func aDisplayWithoutTheHUDHandsTheKeysToMacOS() async throws {
        settings[HUDSettings.replaceSystemHUD] = true
        controller.now = { [start = Date()] in start }              // frozen: the HUD stays up however busy the main actor is
        controller.start()
        defer { controller.stop() }
        let tap = try #require(fake.taps.first)
        _ = tap.handler.handle(MediaKeyEvent(key: .soundUp, isDown: true))
        #expect(await eventually { activity.isActive })
        let calls = fake.volume.calls.count
        environment.canPresentHUD = false                           // the pointer moves to a display with the HUD off
        #expect(await eventually { !activity.isActive })            // the visible HUD goes with it
        #expect(!tap.handler.handle(MediaKeyEvent(key: .soundUp, isDown: true)))     // macOS changes it and shows its HUD
        #expect(!tap.handler.handle(MediaKeyEvent(key: .brightnessUp, isDown: true)))
        #expect(fake.volume.calls.count == calls)                   // Cranny wrote nothing
        #expect(fake.taps.count == 1 && tap.stopCount == 0)         // the tap stays for the way back
        environment.canPresentHUD = true                            // back on a display that shows the HUD
        #expect(await eventually { tap.handler.handle(MediaKeyEvent(key: .soundUp, isDown: true)) })
        #expect(await eventually { activity.isActive })
    }

    @Test func voiceOverActionsAdjustTheLevel() async throws {
        settings[HUDSettings.replaceSystemHUD] = true
        controller.now = { [start = Date()] in start }              // frozen: the HUD stays up however busy the main actor is
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
        controller.now = { [start = Date()] in start }              // frozen: the HUD stays up however busy the main actor is
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

    @Test func theLevelIsFollowedOnlyDuringAVolumeHUD() async throws {
        settings[HUDSettings.replaceSystemHUD] = true
        settings[HUDSettings.keyboardBacklight] = true
        controller.now = { [start = Date()] in start }              // frozen: the HUD stays up however busy the main actor is
        controller.start()
        defer { controller.stop() }
        let tap = try #require(fake.taps.first)
        let observer = try #require(fake.observers.first)
        #expect(observer.isRunning && !observer.followsLevel)       // device changes only while no HUD shows
        _ = tap.handler.handle(MediaKeyEvent(key: .soundUp, isDown: true))
        #expect(await eventually { observer.followsLevel })
        _ = tap.handler.handle(MediaKeyEvent(key: .illuminationUp, isDown: true))
        #expect(await eventually { !observer.followsLevel })        // another kind: no level to follow
        _ = tap.handler.handle(MediaKeyEvent(key: .soundDown, isDown: true))
        #expect(await eventually { observer.followsLevel })
        environment.isScreenLocked = true                           // the HUD goes
        #expect(await eventually { !activity.isActive && !observer.followsLevel })
    }

    @Test func theOutputsEchoOfAPressIsIgnored() async throws {
        settings[HUDSettings.replaceSystemHUD] = true
        let clock = FakeClock()
        controller.now = clock.now
        controller.start()
        defer { controller.stop() }
        let tap = try #require(fake.taps.first)
        let observer = try #require(fake.observers.first)
        let airPods = OutputDevice(id: 2, name: "AirPods Pro", transport: 0x626C_7565)
        _ = tap.handler.handle(MediaKeyEvent(key: .soundUp, isDown: true))
        #expect(await eventually { activity.display?.level == 0.5625 })
        clock.date += 0.1
        observer.emit(VolumeObservation(level: 0.5, isMuted: false, device: airPods, deviceChanged: false))   // late report
        // A device change always counts; with no readable level it keeps the bar. The main actor runs both hops in
        // order, so once its glyph shows, the late report has been handled (and ignored).
        observer.emit(VolumeObservation(level: nil, isMuted: false, device: airPods, deviceChanged: true))
        #expect(await eventually { activity.display?.deviceGlyph == "airpodspro" })
        #expect(activity.display?.level == 0.5625)                  // the bar did not jump back
        clock.date += HUDController.volumeEchoWindow
        observer.emit(VolumeObservation(level: 0.25, isMuted: false, device: airPods, deviceChanged: false))  // Control Center
        #expect(await eventually { activity.display?.level == 0.25 })
    }

    @Test func stopRemovesEverything() async throws {
        settings[HUDSettings.replaceSystemHUD] = true
        controller.now = { [start = Date()] in start }              // frozen: the HUD stays up however busy the main actor is
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
