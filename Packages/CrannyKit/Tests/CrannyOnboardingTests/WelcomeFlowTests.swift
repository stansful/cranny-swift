import AppKit
import CoreGraphics
import CrannyCore
import Foundation
import Testing
@testable import CrannyOnboarding

@MainActor @Suite struct WelcomeFlowTests {
    private final class Outcomes { var values: [WelcomeOutcome] = [] }

    private func makeFlow(trackpad: Bool = true, step: WelcomeStep = .hello,
                          permissions: StaticPermissionGateway = StaticPermissionGateway(),
                          identities: AppIdentityResolver = AppIdentityResolver(locate: { _ in nil }, icon: { _ in nil }))
        -> (WelcomeFlow, ModuleRegistry, RecordingTipPresenter, Outcomes) {
        let registry = makeRegistry(trackpad: trackpad)
        let coach = RecordingTipPresenter()
        let outcomes = Outcomes()
        let flow = WelcomeFlow(registry: registry, permissions: permissions, coach: coach, stage: makeStage(registry),
                               initialStep: step, version: "9.9.9", identities: identities) { outcomes.values.append($0) }
        return (flow, registry, coach, outcomes)
    }

    // MARK: Steps and navigation

    @Test func theRealNotchSaysHiOnStepOne() {
        let (flow, registry, _, _) = makeFlow()
        flow.start(reduceMotion: true)
        #expect(registry.testNotch?.calls == ["flash(hand.wave.fill)"])
        #expect(flow.stage.presentation == .greeting)
        #expect(flow.stage.phase == .compact)                    // Reduce Motion: the "Hi" frame holds still
        #expect(flow.stage.primary == StageGreeting.activityID)
        flow.greetAgain()
        #expect(registry.testNotch?.calls.count == 2)
        flow.stop()
    }

    @Test func forwardAndBackWalkTheVisibleSteps() {
        let (flow, _, _, _) = makeFlow(trackpad: false)
        flow.start(reduceMotion: true)
        #expect(!flow.canGoBack)
        flow.goBack()
        #expect(flow.step == .hello)
        flow.goForward()
        #expect(flow.step == .openIt)
        #expect(flow.stepNumber == 2 && flow.stepCount == 5)
        #expect(!flow.canContinue && flow.offersSkip)            // Skip until the real notch opened
        flow.goForward()                                         // Skip
        #expect(flow.step == .preset)                            // no trackpad: no gesture step
        flow.goBack()
        #expect(flow.step == .openIt)
        #expect(!flow.movedForward)
        flow.stop()
    }

    @Test func aHiddenStartingStepFallsThrough() {
        let (flow, _, _, _) = makeFlow(trackpad: false, step: .gestures)
        #expect(flow.step == .preset)
    }

    @Test func escapeAsksFirst() {
        let (flow, _, _, outcomes) = makeFlow()
        flow.requestSkip()
        #expect(flow.isConfirmingSkip)
        #expect(outcomes.values.isEmpty)
    }

    // MARK: Step 2 · detection on the real notch

    @Test func continueEnablesAfterARealOpening() async throws {
        let (flow, registry, coach, _) = makeFlow(step: .openIt)
        flow.start(reduceMotion: true)
        let notch = try #require(registry.testNotch)
        #expect(coach.isVisible)                                 // "Rest the pointer here, or press ⌃⌥N"
        #expect(coach.shown.last?.keys == "⌃⌥N")
        #expect(coach.shown.last?.isInteractive == false)        // click-through

        notch.emit(.opened(.programmatic))                       // not the person: mirrored, not counted
        #expect(flow.detected.isEmpty)
        #expect(flow.stage.phase == .open)
        #expect(!coach.isVisible)

        notch.emit(.closed)
        #expect(flow.stage.phase == .idle)
        await settle { coach.isVisible }
        #expect(coach.isVisible)

        notch.emit(.opened(.keyboard))
        #expect(flow.detected == [.shortcut])
        #expect(flow.canContinue)
        notch.emit(.opened(.hover))
        #expect(flow.detected == [.shortcut, .hover])
        flow.stop()
    }

    @Test func eventsOutsideStepTwoAreIgnored() throws {
        let (flow, registry, _, _) = makeFlow(step: .preset)
        flow.start(reduceMotion: true)
        try #require(registry.testNotch).emit(.opened(.hover))
        #expect(flow.detected.isEmpty)
        flow.stop()
    }

    @Test func stoppingStopsListening() throws {
        let (flow, registry, coach, _) = makeFlow(step: .openIt)
        flow.start(reduceMotion: true)
        flow.stop()
        #expect(!coach.isVisible)
        try #require(registry.testNotch).emit(.opened(.hover))
        #expect(flow.detected.isEmpty)
    }

    @Test func theCoachMarkGoesWithTheWindowAndTheNotch() async throws {
        let (flow, registry, coach, _) = makeFlow(step: .openIt)
        flow.start(reduceMotion: true)
        let environment = try #require(registry.previewEnvironment)
        let notch = try #require(registry.testNotch)
        #expect(coach.isVisible)
        #expect(coach.anchors.last == TestNotch.closed)

        flow.setWindowVisible(false)                             // behind other windows, on another Space
        #expect(!coach.isVisible)
        flow.setWindowVisible(true)
        #expect(coach.isVisible)

        environment.isScreenLocked = true
        await settle { !coach.isVisible }
        #expect(!coach.isVisible)
        environment.isScreenLocked = false
        await settle { coach.isVisible }
        #expect(coach.isVisible)

        notch.frame = nil                                        // the notch is hidden: nothing to point at
        await settle { !coach.isVisible }
        #expect(!coach.isVisible)
        notch.frame = TestNotch.closed
        await settle { coach.isVisible }

        flow.goForward()                                         // Skip: the coach mark leaves with step 2
        #expect(!coach.isVisible)
        environment.isScreenLocked = true
        environment.isScreenLocked = false
        await settle()
        #expect(!coach.isVisible)                                // and nothing brings it back
        flow.stop()
    }

    @Test func aHiddenWindowHoldsTheStageStill() {
        let (flow, _, _, _) = makeFlow(step: .preset)
        flow.start(reduceMotion: false)
        #expect(flow.stage.isVisibleOnScreen)
        #expect(flow.stage.theme.motion == .standard)
        flow.setWindowVisible(false)
        #expect(!flow.stage.isVisibleOnScreen)
        #expect(flow.stage.theme.motion == .instant)             // every effect's budget holds a resting frame
        flow.setWindowVisible(true)
        #expect(flow.stage.theme.motion == .standard)
        flow.stop()
    }

    @Test func choosingAWayInWritesTheSetting() {
        let (flow, registry, coach, _) = makeFlow(step: .openIt)
        flow.start(reduceMotion: true)
        let settings = registry.services.settings
        flow.choose(.click)
        #expect(settings[CoreSettings.openMode] == .click)
        #expect(flow.coachContent().keys == "⌃⌥N")
        #expect(coach.shown.count >= 2)                          // the coach mark follows the choice
        flow.setHoverDelay(.long)
        #expect(settings[CoreSettings.hoverDelay] == .long)
        #expect(settings[CoreSettings.openMode] == .hover)       // picking a delay picks Hover
        flow.choose(.shortcut)
        #expect(settings[CoreSettings.openMode] == .shortcutOnly)
        settings[CoreSettings.shortcuts] = [.openNook: nil]
        #expect(flow.coachContent().keys == nil)
        flow.stop()
    }

    // MARK: Step 3 · practice

    @Test func pullingDownOpensThePracticeNotch() {
        let (flow, _, _, _) = makeFlow(step: .gestures)
        flow.start(reduceMotion: true)
        #expect(!flow.practisesTrackSwipe)                       // nothing plays in previews
        #expect(!flow.canContinue)
        var t: TimeInterval = 0
        func sample(_ phase: SwipePhase, _ dy: CGFloat) -> ScrollSample {
            t += 1.0 / 60
            return ScrollSample(phase: phase, isMomentum: false, deltaX: 0, deltaY: dy, isPrecise: true,
                                isInvertedFromDevice: true, timestamp: t)
        }
        flow.handleScroll(sample(.began, 0))
        flow.handleScroll(sample(.changed, 8))
        #expect(flow.stage.gestureTranslation.height > 0)
        flow.handleScroll(sample(.changed, 10))
        flow.handleScroll(sample(.changed, 10))
        flow.handleScroll(sample(.ended, 0))
        #expect(flow.pulledDown)
        #expect(flow.canContinue)
        #expect(flow.stage.phase == .open)
        #expect(flow.stage.gestureTranslation == .zero)
        flow.stop()
    }

    // MARK: Step 4 · layout

    @Test func pickingAPresetRewritesHome() {
        let (flow, registry, _, _) = makeFlow(step: .preset)
        flow.start(reduceMotion: true)
        #expect(flow.selectedPreset == .listener)
        #expect(flow.stage.phase == .open)
        flow.pick(.minimal)
        #expect(registry.services.settings[CoreSettings.pages].first?.items == NookPreset.minimal.items)
        #expect(flow.selectedPreset == .minimal)
        #expect(flow.stage.openColumns == 4)
        flow.stop()
    }

    @Test func pickingAPresetSetsTypeToCapture() {
        let (flow, registry, _, _) = makeFlow(step: .preset)
        registry.add(captureTarget: CaptureTarget(id: "notes", title: "Notes", symbol: "note.text", widget: .notes) { _ in .notes })
        registry.add(captureTarget: CaptureTarget(id: "todos", title: "To-dos", symbol: "checklist", widget: .todos) { _ in .todos })
        let settings = registry.services.settings
        flow.start(reduceMotion: true)
        #expect(settings[CoreSettings.typeToCapture] == nil)                 // a fresh install: Off (ruling E2)
        flow.pick(.maker)
        #expect(settings[CoreSettings.typeToCapture] == "notes")
        flow.pick(.meetings)
        #expect(settings[CoreSettings.typeToCapture] == nil)                 // Notes is on no page any more
        flow.stop()
    }

    // MARK: Step 5 · permissions

    @Test func permissionRowsFollowTheLayoutAndAskOnlyOnAllow() async throws {
        let gateway = StaticPermissionGateway([.calendar: .granted])
        let (flow, registry, _, _) = makeFlow(step: .permissions, permissions: gateway,
                                              identities: await installedApps(["com.apple.Music", "com.spotify.client"]))
        flow.start(reduceMotion: true)
        #expect(gateway.refreshCount == 1)
        #expect(gateway.requested.isEmpty)                       // nothing is asked on its own
        // First run: the Apple Events fallback and "every Bluetooth device" are off, so a grant would do nothing.
        #expect(flow.permissionRows.map(\.group) == [.calendar, .accessibility])
        #expect(flow.stage.height == WelcomeMetrics.compactStageHeight)      // the rows get the room

        let settings = registry.services.settings                // switched on in Settings: the rows are offered
        settings[SamplePermissionOptIns.appleEvents] = true
        settings[SamplePermissionOptIns.allBluetoothDevices] = true
        let rows = flow.permissionRows
        #expect(rows.map(\.group) == [.calendar, .accessibility, .automation, .bluetooth])
        #expect(flow.state(of: rows[0]) == .granted)

        let automation = try #require(rows.first { $0.group == .automation })
        gateway.answers[.automation(bundleID: "com.spotify.client")] = .unknown   // Spotify is not running
        await flow.allow(automation)
        #expect(gateway.requested == automation.kinds)
        #expect(flow.state(of: automation) == .deferred)

        flow.pick(.maker)
        #expect(flow.permissionRows.map(\.group) == [.accessibility, .bluetooth])
        flow.openSystemSettings(flow.permissionRows[0])
        #expect(gateway.openedSettings == [.accessibility])
        settings[SamplePermissionOptIns.allBluetoothDevices] = false
        #expect(flow.permissionRows.map(\.group) == [.accessibility])
        flow.stop()
    }

    /// Automation is offered only for players that are installed, once that is known (a player installed meanwhile
    /// appears without a relaunch: `aPlayerInstalledMeanwhileIsOfferedWithoutARelaunch`).
    @Test func automationIsOfferedOnlyForInstalledPlayers() async throws {
        let (flow, registry, _, _) = makeFlow(step: .permissions, identities: await installedApps(["com.apple.Music"]))
        flow.start(reduceMotion: true)
        registry.services.settings[SamplePermissionOptIns.appleEvents] = true
        let automation = try #require(flow.permissionRows.first { $0.group == .automation })
        #expect(automation.kinds == [.automation(bundleID: "com.apple.Music")])               // Spotify is not installed
        flow.stop()

        let (pending, pendingRegistry, _, _) = makeFlow(step: .permissions,
                                                        identities: AppIdentityResolver(locate: { _ in
                                                            try? await Task.sleep(for: .seconds(60)); return nil
                                                        }, icon: { _ in nil }))
        pending.start(reduceMotion: true)
        pendingRegistry.services.settings[SamplePermissionOptIns.appleEvents] = true
        #expect(!pending.permissionRows.contains { $0.group == .automation })                // not known yet: no row
        pending.stop()
    }

    /// Step 5 looks the apps up again when it appears and whenever Cranny becomes active (back from installing a
    /// player), so a player installed after its first lookup gets its Automation kind without a relaunch.
    @Test func aPlayerInstalledMeanwhileIsOfferedWithoutARelaunch() async throws {
        let music = PermissionKind.automation(bundleID: "com.apple.Music")
        let spotify = PermissionKind.automation(bundleID: "com.spotify.client")
        let installs = FakeInstalls()
        let identities = await installs.resolver(lookingUp: ["com.apple.Music", "com.spotify.client"])  // neither yet
        let (flow, registry, _, _) = makeFlow(step: .preset, identities: identities)
        registry.services.settings[SamplePermissionOptIns.appleEvents] = true
        flow.start(reduceMotion: true)
        func automationKinds() -> [PermissionKind] { flow.permissionRows.first { $0.group == .automation }?.kinds ?? [] }
        #expect(automationKinds().isEmpty)

        installs.install("com.apple.Music")                     // installed while step 4 shows
        flow.goForward()                                         // step 5 appears: looked up again
        #expect(flow.step == .permissions)
        await settle { automationKinds() == [music] }
        #expect(automationKinds() == [music])

        installs.install("com.spotify.client")                  // installed while the window is open
        NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: nil)   // back in Cranny
        await settle { automationKinds() == [music, spotify] }
        #expect(automationKinds() == [music, spotify])
        flow.stop()
    }

    /// The row waits for an Automation answer still on its way instead of offering "Allow" (the players may be allowed
    /// already), then shows the answer.
    @Test func anAutomationRowWaitsForItsFirstAnswer() async throws {
        let music = PermissionKind.automation(bundleID: "com.apple.Music")
        let gateway = StaticPermissionGateway([music: .granted])
        gateway.checking = [music]
        let (flow, registry, _, _) = makeFlow(step: .permissions, permissions: gateway,
                                              identities: await installedApps(["com.apple.Music"]))
        flow.start(reduceMotion: true)
        registry.services.settings[SamplePermissionOptIns.appleEvents] = true
        let automation = try #require(flow.permissionRows.first { $0.group == .automation })
        #expect(flow.state(of: automation) == .checking)
        gateway.checking = []                                    // the answer lands
        #expect(flow.state(of: automation) == .granted)
        flow.stop()
    }

    // MARK: Endings

    @Test func aPermissionStepWithoutRowsKeepsTheFullStage() {
        let registry = ModuleRegistry(services: .preview())                  // no module declared anything
        let flow = WelcomeFlow(registry: registry, permissions: StaticPermissionGateway(), coach: RecordingTipPresenter(),
                               stage: makeStage(registry), initialStep: .permissions, version: "9.9.9") { _ in }
        flow.start(reduceMotion: true)
        #expect(flow.permissionRows.isEmpty)
        #expect(flow.stage.height == WelcomeMetrics.stageHeight)
        flow.stop()
    }

    @Test func doneRecordsOpensOnceAndTurnsOnLaunchAtLogin() throws {
        let (flow, registry, _, outcomes) = makeFlow(step: .done)
        flow.start(reduceMotion: true)
        #expect(flow.stage.height == WelcomeMetrics.compactStageHeight)
        #expect(flow.isLastStep)
        #expect(flow.launchesAtLogin)                            // on by default on the first run
        flow.finish(.done)
        flow.finish(.done)
        #expect(outcomes.values == [.done])
        #expect(registry.services.settings[CoreSettings.onboardingCompletedVersion] == "9.9.9")
        #expect(registry.testNotch?.calls.contains("open(nook,-,programmatic)") == true)
        #expect(registry.previewApp?.loginItem == .enabled)
    }

    @Test func theTourKeepsTheLoginItemOffWhenAskedTo() {
        let (flow, registry, _, outcomes) = makeFlow(step: .done)
        flow.launchesAtLogin = false
        flow.finish(.tour)
        #expect(outcomes.values == [.tour])
        #expect(registry.previewApp?.loginItem == .disabled)
        #expect(registry.testNotch?.calls.contains("open(nook,-,programmatic)") == false)
    }

    @Test func skippingRecordsCompletionButChangesNothingElse() {
        let (flow, registry, _, outcomes) = makeFlow(step: .openIt)
        flow.start(reduceMotion: true)
        flow.requestSkip()
        flow.finish(.skipped)
        #expect(outcomes.values == [.skipped])
        #expect(!flow.isConfirmingSkip)
        #expect(registry.services.settings[CoreSettings.onboardingCompletedVersion] == "9.9.9")
        #expect(registry.previewApp?.loginItem == .disabled)
        #expect(registry.services.settings[CoreSettings.openMode] == .hover)
    }

    @Test func aRerunReflectsTheCurrentLoginItem() {
        let registry = makeRegistry()
        registry.services.settings[CoreSettings.onboardingCompletedVersion] = "0.1.0"
        let flow = WelcomeFlow(registry: registry, permissions: StaticPermissionGateway(), coach: RecordingTipPresenter(),
                               stage: makeStage(registry), version: "9.9.9") { _ in }
        #expect(!flow.launchesAtLogin)                           // disabled now, and not the first run
        flow.finish(.done)
        #expect(registry.previewApp?.loginItem == .disabled)
    }
}

@MainActor @Suite struct StageSceneTests {
    @Test func closedAndCompactDrawAtFullSizeAndOpenScalesToFit() {
        let layout = NotchLayout(metrics: .reference)
        let size = CGSize(width: 640, height: 216)
        #expect(StageScene.fitScale(for: layout.closed, in: size) == 1)
        #expect(StageScene.fitScale(for: layout.compact(.medium), in: size) == 1)
        let open = StageScene.fitScale(for: layout.open(columns: 10), in: size)
        #expect(open < 1 && open >= WelcomeMetrics.minimumStageScale)
        #expect(layout.open(columns: 10).outerWidth * open <= size.width - 2 * WelcomeMetrics.stageMargin + 0.5)
        #expect(StageScene.fitScale(for: .zero, in: size) == 1)
    }

    @Test func theStageIsAPreview() {
        let registry = makeRegistry()
        let stage = makeStage(registry)
        stage.show(.open, reduceMotion: true)
        #expect(stage.isPreview)
        #expect(stage.phase == .open)
        #expect(stage.openColumns == 10)
        stage.show(.practice(withTrack: true), reduceMotion: true)   // no media module: no sample track
        #expect(stage.phase == .idle)
        stage.setGesture(CGSize(width: 0, height: 4))
        #expect(stage.gestureTranslation.height == 4)
        stage.show(.idle, reduceMotion: true)
        #expect(stage.gestureTranslation == .zero)
    }

    @Test func hidingTheWindowHoldsTheStageStill() {
        let stage = makeStage(makeRegistry())
        stage.show(.open, reduceMotion: false)
        stage.setVisibleOnScreen(false)
        #expect(stage.theme.motion == .instant)
        // Tripwire: once NotchSceneModel has `isVisibleOnScreen` (its canvas budget reads it),
        // the stage must clear it as well.
        let visibility = Mirror(reflecting: stage.model).children.first { $0.label == "_isVisibleOnScreen" }?.value
        if let visibility = visibility as? Bool { #expect(visibility == false) }
        stage.setVisibleOnScreen(true)
        #expect(stage.theme == CrannyTheme())
    }

    @Test func oneLightAtATime() {
        var theme = CrannyTheme()
        #expect(StageBackdrop.level(theme: theme, panelDrawsLight: false) == .subtle)
        #expect(StageBackdrop.level(theme: theme, panelDrawsLight: true) == .off)      // the open panel's light only
        theme.ambience = .vivid
        #expect(StageBackdrop.level(theme: theme, panelDrawsLight: false) == .subtle)  // the brand aurora stays Subtle
        theme.reduceTransparency = true
        #expect(StageBackdrop.level(theme: theme, panelDrawsLight: false) == .off)     // Reduce Transparency: no light
        theme = CrannyTheme()
        theme.ambience = .off
        #expect(StageBackdrop.level(theme: theme, panelDrawsLight: false) == .off)     // Ambient light off
    }

    @Test func firstLightPlaysOnceAndNeverUnderReduceMotion() {
        let calm = makeStage(makeRegistry())
        calm.show(.open, reduceMotion: true)
        #expect(calm.delightSerial == 0)

        let stage = makeStage(makeRegistry())
        stage.show(.open, reduceMotion: false)
        #expect(stage.delight == .firstLight)
        #expect(stage.delightSerial == 1)
        stage.setOpen(false)
        stage.setOpen(true)
        #expect(stage.delightSerial == 1)
    }

    @Test func theGreetingPlaysThenLeaves() async {
        let stage = makeStage(makeRegistry())
        stage.show(.greeting, reduceMotion: false)
        #expect(stage.phase == .idle)
        await settle { stage.phase == .compact }
        #expect(stage.phase == .compact)
        stage.stop()
    }
}
