// The model on fakes, driven through the Core doubles (PreviewNotchControl, PreviewSystemEnvironment):
// ARCHITECTURE.md §10.5 acceptance — never starts without a click; stops ≤ 1 s after close, page change, lock,
// sleep; never runs in previews; the panel is held open only while the permission prompt is up.
import CrannyCore
import Foundation
import Testing
@testable import CrannyMirror

@MainActor struct MirrorModelTests {
    // MARK: Never starts by itself

    @Test func neverStartsWithoutAClick() async {
        let h = MirrorHarness()
        await h.show()
        h.notch.emit(.opened(.hover))
        h.notch.emit(.pinned(true))
        h.environment.isScreenLocked = true
        h.environment.isScreenLocked = false
        h.discovery.change(Cameras.two)
        h.settings[MirrorSettings.cameraID] = Cameras.iPhone.id
        try? await Task.sleep(for: .milliseconds(50))
        #expect(h.controller.starts.isEmpty)
        #expect(h.model.phase == .off)
        #expect(h.authorization.requests == 0)
    }

    @Test func aClickStartsTheResolvedCamera() async {
        let h = MirrorHarness()
        await h.show()
        await h.model.tap()
        #expect(h.controller.starts == [Cameras.builtIn.id])
        #expect(h.model.phase == .starting(deviceID: Cameras.builtIn.id))
        h.controller.send(.started(deviceID: Cameras.builtIn.id))
        #expect(h.model.phase == .running(deviceID: Cameras.builtIn.id))
        #expect(h.model.feed != nil)
        #expect(h.model.presentation(isLive: true).showsFeed)
    }

    @Test func aClickWhileNoLiveWidgetIsVisibleDoesNothing() async {
        let h = MirrorHarness()
        await h.model.tap()
        #expect(h.controller.starts.isEmpty)
    }

    @Test func previewsAndLayoutEditingNeverRunTheCamera() async {
        // Stage, onboarding and #Preview contexts never register as visible, so a click cannot start anything.
        let size = CGSize(width: 120, height: 120)
        #expect(!MirrorVisibility.isLive(WidgetContext(cells: 2, contentSize: size, isPreview: true)))
        #expect(!MirrorVisibility.isLive(WidgetContext(cells: 2, contentSize: size, isEditingLayout: true)))
        #expect(MirrorVisibility.isLive(WidgetContext(cells: 2, contentSize: size)))
        let h = MirrorHarness()
        #expect(h.model.presentation(isLive: false) == MirrorPresentation(message: MirrorCopy.previewCamera))
        await h.model.tap()
        #expect(h.controller.starts.isEmpty)
    }

    @Test func aSecondClickTurnsItOff() async {
        let h = MirrorHarness()
        await h.run()
        await h.model.tap()
        #expect(h.controller.stops == 1)
        #expect(h.model.phase == .off)
        #expect(h.model.feed == nil)
    }

    // MARK: Stops (≤ 1 s)

    @Test func stopsWhenThePanelCloses() async {
        let h = MirrorHarness()
        await h.run()
        h.notch.emit(.closed)
        #expect(h.controller.stops == 1)
        #expect(h.model.phase == .off)
    }

    @Test func stopsWhenThePageChanges() async {
        let h = MirrorHarness()
        await h.run()
        h.notch.emit(.pageChanged(.tray))
        #expect(h.controller.stops == 1)
        #expect(h.model.phase == .off)
    }

    @Test func stopsWhenTheScreenLocks() async {
        let h = MirrorHarness()
        await h.run()
        h.environment.isScreenLocked = true
        #expect(await eventually(within: .seconds(1)) { h.controller.stops == 1 })
        #expect(h.model.phase == .off)
    }

    @Test func stopsWhenTheDisplaysSleep() async {
        let h = MirrorHarness()
        await h.run()
        h.environment.areDisplaysAsleep = true
        #expect(await eventually(within: .seconds(1)) { h.controller.stops == 1 })
        #expect(h.model.phase == .off)
    }

    @Test func stopsWhenTheWidgetDisappears() async {
        let h = MirrorHarness()
        let id = await h.run()
        h.model.viewDisappeared(id)
        #expect(h.controller.stops == 1)
        #expect(h.model.phase == .off)
    }

    @Test func stopsOnSystemSleepAndTermination() async {
        let h = MirrorHarness()
        await h.run()
        h.model.halt(.systemSleep)
        #expect(h.controller.stops == 1)
        await h.model.tap()
        h.controller.send(.started(deviceID: Cameras.builtIn.id))
        h.model.shutdown()
        #expect(h.controller.stops == 2)
        #expect(!h.discovery.isWatching)
        // After shutdown the notch observer is gone: nothing reacts any more.
        h.notch.emit(.closed)
        #expect(h.controller.stops == 2)
    }

    @Test func aLockedScreenRefusesClicks() async {
        let h = MirrorHarness()
        await h.show()
        h.environment.isScreenLocked = true
        await h.model.tap()
        #expect(h.controller.starts.isEmpty)
    }

    @Test func aRestartAfterAHaltNeedsANewClick() async {
        let h = MirrorHarness()
        await h.run()
        h.notch.emit(.closed)
        let id = await h.show()                       // the panel opens again
        _ = id
        try? await Task.sleep(for: .milliseconds(20))
        #expect(h.controller.starts.count == 1)
        #expect(h.model.phase == .off)
    }

    @Test func aStartThatCompletesAfterAHaltIsReleased() async {
        let h = MirrorHarness()
        await h.show()
        await h.model.tap()
        h.notch.emit(.closed)
        #expect(h.controller.stops == 1)
        h.controller.send(.started(deviceID: Cameras.builtIn.id))
        #expect(h.controller.stops == 2)
        #expect(h.model.phase == .off)
    }

    // MARK: Permission

    @Test func askingForAccessHoldsThePanelOpenUntilAnswered() async {
        let h = MirrorHarness(.notDetermined)
        await h.show()
        await h.model.tap()
        #expect(h.model.phase == .requestingAccess)
        #expect(await eventually { h.authorization.isPromptShowing })
        #expect(h.holds == ["hold(true,mirror.permission)"])
        #expect(h.controller.starts.isEmpty)

        h.authorization.answer(.granted)
        #expect(await eventually { h.model.phase == .starting(deviceID: Cameras.builtIn.id) })
        #expect(h.holds == ["hold(true,mirror.permission)", "hold(false,mirror.permission)"])
        #expect(h.controller.starts == [Cameras.builtIn.id])
    }

    @Test func refusingAccessReleasesTheHoldAndOffersSettings() async {
        let h = MirrorHarness(.notDetermined)
        await h.show()
        await h.model.tap()
        #expect(await eventually { h.authorization.isPromptShowing })
        h.authorization.answer(.denied)
        #expect(await eventually { h.holds.count == 2 })
        #expect(h.model.phase == .off)
        let shown = h.model.presentation(isLive: true)
        #expect(shown.message == MirrorCopy.accessOff)
        #expect(shown.action == .openSettings)
        await h.model.tap()
        #expect(h.authorization.settingsOpened == 1)
        #expect(h.controller.starts.isEmpty)
    }

    @Test func closingDuringThePromptReleasesTheHoldAndNeverStarts() async {
        let h = MirrorHarness(.notDetermined)
        await h.show()
        await h.model.tap()
        #expect(await eventually { h.authorization.isPromptShowing })
        h.notch.emit(.closed)
        #expect(h.holds == ["hold(true,mirror.permission)", "hold(false,mirror.permission)"])
        h.authorization.answer(.granted)
        try? await Task.sleep(for: .milliseconds(30))
        #expect(h.controller.starts.isEmpty)
        #expect(h.model.phase == .off)
        #expect(h.holds.count == 2)                   // every true got exactly one false
    }

    @Test func revokedAccessIsReReadOnTheNextClick() async {
        let h = MirrorHarness()
        await h.run()
        h.controller.send(.failed(.notAuthorized))
        #expect(h.model.phase == .problem(.notAuthorized))
        h.authorization.status = .denied
        await h.model.tap()
        #expect(h.authorization.forcedRefreshes == 1)
        #expect(h.authorization.settingsOpened == 1)
    }

    // MARK: Cameras

    @Test func pickingAnotherCameraWhileRunningSwitches() async {
        let h = MirrorHarness()
        await h.run()
        h.model.selectedCameraID = Cameras.iPhone.id
        #expect(await eventually { h.controller.starts == [Cameras.builtIn.id, Cameras.iPhone.id] })
        #expect(h.model.phase == .starting(deviceID: Cameras.iPhone.id))
        #expect(h.settings[MirrorSettings.cameraID] == Cameras.iPhone.id)
    }

    @Test func hotPlugUpdatesTheList() async {
        let h = MirrorHarness(cameras: Cameras.builtInOnly)
        await h.show()
        h.discovery.change(CameraSnapshot(devices: [Cameras.builtIn, Cameras.usb], systemPreferredID: Cameras.builtIn.id))
        #expect(await eventually { h.model.catalog.devices.map(\.id) == [Cameras.builtIn.id, Cameras.usb.id] })
        #expect(h.controller.starts.isEmpty)          // a new camera never starts anything
    }

    @Test func unpluggingTheRunningCameraStopsAndSaysSo() async {
        let h = MirrorHarness()
        h.settings[MirrorSettings.cameraID] = Cameras.iPhone.id
        await h.run()
        #expect(h.controller.starts == [Cameras.iPhone.id])
        h.discovery.change(Cameras.builtInOnly)
        #expect(await eventually { h.model.phase == .problem(.disconnected) })
        #expect(h.controller.stops == 1)
        #expect(h.controller.starts.count == 1)       // never switches to another camera on its own
        #expect(h.model.presentation(isLive: true).actionTitle == MirrorCopy.tryAgain)
    }

    @Test func aClosedLidExplainsAndOpeningItClearsTheMessage() async {
        let h = MirrorHarness(cameras: Cameras.lidClosed)
        await h.show()
        #expect(h.model.presentation(isLive: true).detail == MirrorCopy.lidClosed)
        await h.model.tap()
        #expect(h.model.phase == .problem(.suspended))
        #expect(h.controller.starts.isEmpty)
        h.discovery.change(Cameras.builtInOnly)
        #expect(await eventually { h.model.phase == .off })
        #expect(h.controller.starts.isEmpty)
    }

    @Test func noCameraSaysSo() async {
        let h = MirrorHarness(cameras: Cameras.none)
        await h.show()
        #expect(h.model.presentation(isLive: true).message == MirrorCopy.noCamera)
        await h.model.tap()
        #expect(h.model.phase == .problem(.noCamera))
        #expect(h.controller.starts.isEmpty)
    }

    @Test func aRuntimeFailureStopsAndOffersARetry() async {
        let h = MirrorHarness()
        await h.run()
        h.controller.send(.failed(.sessionFailed))
        #expect(h.controller.stops == 1)
        #expect(h.model.phase == .problem(.sessionFailed))
        await h.model.tap()
        #expect(h.controller.starts.count == 2)
    }

    @Test func flipWritesTheSetting() {
        let h = MirrorHarness()
        #expect(h.model.isMirrored)
        h.model.isMirrored = false
        #expect(h.settings[MirrorSettings.isMirrored] == false)
    }
}
