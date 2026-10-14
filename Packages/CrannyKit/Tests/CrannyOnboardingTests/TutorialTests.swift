import CoreGraphics
import CrannyCore
import Foundation
import Testing
@testable import CrannyOnboarding

@Suite struct TutorialRunTests {
    @Test func fiveStepsOnlyWhileSomethingPlays() {
        #expect(TutorialRun(includesTrackSwipe: true).count == 5)
        let run = TutorialRun(includesTrackSwipe: false)
        #expect(run.count == 4)
        #expect(!run.steps.contains(.swipeTrack))
        #expect(run.current == .reachNotch)
        #expect(run.number == 1)
    }

    @Test func reachingTheNotchNeedsThePersonsOwnOpening() {
        var run = TutorialRun(includesTrackSwipe: false)
        let r1 = run.handle(.opened(.programmatic))
        #expect(!r1)
        let r2 = run.handle(.opened(.tutorial))
        #expect(!r2)
        let r3 = run.handle(.closed)
        #expect(!r3)
        let r4 = run.handle(.opened(.hover))
        #expect(r4)
        var keyboard = TutorialRun(includesTrackSwipe: false)
        let r5 = keyboard.handle(.opened(.keyboard))
        #expect(r5)
    }

    @Test func eachStepWaitsForItsOwnEvent() {
        var run = TutorialRun(includesTrackSwipe: true)
        run.jump(to: 1)
        #expect(run.current == .dropFile)
        let r6 = run.handle(.filesCaught(count: 0))
        #expect(!r6)
        let r7 = run.handle(.commandHintsShown)
        #expect(!r7)
        let r8 = run.handle(.filesCaught(count: 2))
        #expect(r8)
        run.advance(isPlaying: true)
        #expect(run.current == .swipeTrack)
        let r9 = run.handle(.activityGesture(.nowPlaying, .swipeLeft))
        #expect(r9)
        run.advance(isPlaying: true)
        #expect(run.current == .holdCommand)
        let r10 = run.handle(.commandHintsShown)
        #expect(r10)
    }

    @Test func pinThenEscape() {
        var run = TutorialRun(includesTrackSwipe: false)
        run.jump(to: 3)
        #expect(run.current == .pinAndClose)
        let r11 = run.handle(.closed)
        #expect(!r11)                         // closing without the pin does not count
        let r12 = run.handle(.pinned(true))
        #expect(!r12)
        let r13 = run.handle(.pinned(false))
        #expect(!r13)                  // unpinned again
        let r14 = run.handle(.closed)
        #expect(!r14)
        let r15 = run.handle(.pinned(true))
        #expect(!r15)
        let r16 = run.handle(.closed)
        #expect(r16)
        run.advance(isPlaying: false)
        #expect(run.isFinished)
        #expect(run.number == 4)
    }

    @Test func aPinFromAnEarlierStepCounts() {
        var run = TutorialRun(includesTrackSwipe: false)
        run.jump(to: 2)                                       // "Hold ⌘": the person pins on the way
        let r1 = run.handle(.pinned(true))
        #expect(!r1)
        let r2 = run.handle(.commandHintsShown)
        #expect(r2)
        run.advance(isPlaying: false)
        #expect(run.current == .pinAndClose)
        #expect(run.isPinned)                                 // not forgotten when the step changes
        let r3 = run.handle(.closed)                          // Esc while pinned
        #expect(r3)
    }

    @Test func theCloseThatEndsThePinStillCounts() {
        // The shell emits `.closed`, then the `.pinned(false)` of the pin that close ended.
        var run = TutorialRun(includesTrackSwipe: false, isPinned: true)
        run.jump(to: 3)
        let closed = run.handle(.closed)
        #expect(closed)
        let unpinned = run.handle(.pinned(false))
        #expect(!unpinned)
        #expect(!run.isPinned)
    }

    @Test func theTrackStepIsDroppedWhenMusicStopped() {
        var run = TutorialRun(includesTrackSwipe: true)
        run.jump(to: 1)
        run.advance(isPlaying: false)
        #expect(run.current == .holdCommand)
        #expect(run.count == 4)
        #expect(run.number == 3)
    }

    @Test func jumpsClamp() {
        var run = TutorialRun(includesTrackSwipe: false)
        run.jump(to: 99)
        #expect(run.current == .pinAndClose)
        run.jump(to: -3)
        #expect(run.current == .reachNotch)
    }
}

@MainActor @Suite struct TutorialControllerTests {
    @Test func aStepCompletesOnlyOnRealDetection() async throws {
        let registry = makeRegistry()
        let presenter = RecordingTipPresenter()
        let tutorial = TutorialController(registry: registry, presenter: presenter, celebration: .milliseconds(1),
                                          farewell: .seconds(60))
        tutorial.start()
        let first = try #require(presenter.shown.last)
        #expect(first.mark == .symbol("cursorarrow.motionlines"))
        #expect(first.keys == "⌃⌥N")
        #expect(first.isInteractive)                          // "Skip tour" is always there
        #expect(first.progress != nil)

        let notch = try #require(registry.testNotch)
        notch.emit(.closed)
        notch.emit(.filesCaught(count: 1))                    // not this step's event
        #expect(presenter.shown.allSatisfy { $0.mark != .done })

        notch.emit(.opened(.hover))
        #expect(presenter.shown.last?.mark == .done)          // ✓ before moving on
        await settle { presenter.shown.last?.mark == .symbol("tray.and.arrow.down.fill") }
        #expect(presenter.shown.last?.mark == .symbol("tray.and.arrow.down.fill"))
        tutorial.stop()
    }

    @Test func theWholeTourRecordsCompletion() async throws {
        let registry = makeRegistry()
        let presenter = RecordingTipPresenter()
        let tutorial = TutorialController(registry: registry, presenter: presenter, celebration: .milliseconds(1),
                                          farewell: .milliseconds(20))
        let notch = try #require(registry.testNotch)
        tutorial.start()                                      // nothing plays: four steps
        let events: [[NotchEvent]] = [[.opened(.click)], [.filesCaught(count: 3)], [.commandHintsShown], [.pinned(true), .closed]]
        for batch in events {
            let before = presenter.shown.count
            for event in batch { notch.emit(event) }
            await settle { presenter.shown.count > before + 1 }
        }
        await settle { registry.services.settings[CoreSettings.tutorialCompleted] }
        #expect(registry.services.settings[CoreSettings.tutorialCompleted])
        #expect(presenter.shown.last?.actionTitle != nil)     // the closing bubble has a Done button
        await settle { !tutorial.isRunning }
        #expect(!tutorial.isRunning)
        #expect(!presenter.isVisible)
    }

    @Test func skippingStopsListeningAndRecordsNothing() async throws {
        let registry = makeRegistry()
        let presenter = RecordingTipPresenter()
        let tutorial = TutorialController(registry: registry, presenter: presenter, celebration: .milliseconds(1))
        tutorial.start()
        presenter.pressAction()                               // "Skip tour"
        #expect(!tutorial.isRunning)
        #expect(!presenter.isVisible)
        let shown = presenter.shown.count
        registry.testNotch?.emit(.opened(.hover))
        await settle()
        #expect(presenter.shown.count == shown)
        #expect(!registry.services.settings[CoreSettings.tutorialCompleted])
    }

    @Test func theShortcutStepFollowsTheBinding() {
        let registry = makeRegistry()
        registry.services.settings[CoreSettings.shortcuts] = [.openNook: nil]
        let presenter = RecordingTipPresenter()
        let tutorial = TutorialController(registry: registry, presenter: presenter)
        tutorial.start()
        #expect(presenter.shown.last?.keys == nil)
        #expect(presenter.shown.last?.text == OpenPrompt.rest(orPress: false).tutorialText)
        tutorial.stop()
    }

    @Test func theFirstStepFollowsTheWayInChosenInTheWelcome() async {
        let registry = makeRegistry()
        let settings = registry.services.settings
        settings[CoreSettings.openMode] = .click
        let presenter = RecordingTipPresenter()
        let tutorial = TutorialController(registry: registry, presenter: presenter)
        tutorial.start()
        #expect(presenter.shown.last?.text == OpenPrompt.click(orPress: true).tutorialText)
        #expect(presenter.shown.last?.text != OpenPrompt.rest(orPress: true).tutorialText)   // never "rest the pointer"
        #expect(presenter.shown.last?.keys == "⌃⌥N")

        settings[CoreSettings.openMode] = .shortcutOnly                                   // changed while waiting
        await settle { presenter.shown.last?.text == OpenPrompt.press.tutorialText }
        #expect(presenter.shown.last?.text == OpenPrompt.press.tutorialText)
        #expect(presenter.shown.last?.mark == .symbol("keyboard"))

        settings[CoreSettings.shortcuts] = [.openNook: nil]                               // nothing to press: click
        await settle { presenter.shown.last?.text == OpenPrompt.noShortcut.tutorialText }
        #expect(presenter.shown.last?.text == OpenPrompt.click(orPress: false).tutorialText)
        #expect(presenter.shown.last?.keys == nil)
        tutorial.stop()
    }

    @Test func theBubbleHidesWithTheNotchAndComesBackWhereItWas() async throws {
        let registry = makeRegistry()
        let environment = try #require(registry.previewEnvironment)
        let notch = try #require(registry.testNotch)
        let presenter = RecordingTipPresenter()
        let tutorial = TutorialController(registry: registry, presenter: presenter, celebration: .milliseconds(1))
        tutorial.startForVisualQA(atStep: 2)                   // "Drag any file onto the notch"
        #expect(presenter.isVisible)

        environment.isFullScreenInFront = true                 // the notch hides over full screen…
        await settle { !presenter.isVisible }
        #expect(!presenter.isVisible)
        #expect(tutorial.isRunning)                            // …the tour waits
        registry.services.settings[CoreSettings.fullScreenPolicy] = .showAll
        await settle { presenter.isVisible }                   // …unless the notch shows everything there
        #expect(presenter.isVisible)
        environment.isFullScreenInFront = false
        registry.services.settings[CoreSettings.fullScreenPolicy] = .alertsAndHUD

        for hide in [{ environment.isScreenLocked = true }, { environment.areDisplaysAsleep = true },
                     { environment.areLiveActivitiesPaused = true }, { notch.frame = nil },
                     { notch.frame = .zero }] as [@MainActor () -> Void] {
            hide()
            await settle { !presenter.isVisible }
            #expect(!presenter.isVisible)
            environment.isScreenLocked = false
            environment.areDisplaysAsleep = false
            environment.areLiveActivitiesPaused = false
            notch.frame = TestNotch.closed
            await settle { presenter.isVisible }
            #expect(presenter.isVisible)
            #expect(presenter.shown.last?.mark == .symbol("tray.and.arrow.down.fill"))   // still the same step
            #expect(presenter.anchors.last == TestNotch.closed)
        }

        notch.frame = nil                                      // a step done while hidden: no ✓ is drawn anywhere
        await settle { !presenter.isVisible }
        let shown = presenter.shown.count
        notch.emit(.filesCaught(count: 1))
        #expect(presenter.shown.count == shown)
        tutorial.stop()
    }

    @Test func theBubbleFollowsTheShapeWithoutAnEvent() async throws {
        let registry = makeRegistry()
        let notch = try #require(registry.testNotch)
        let presenter = RecordingTipPresenter()
        let tutorial = TutorialController(registry: registry, presenter: presenter)
        tutorial.start()
        let peek = CGRect(x: 600, y: 900, width: 312, height: 82)
        notch.frame = peek                                     // a peek appeared: no `NotchEvent` for that
        await settle { presenter.anchors.last == peek }
        #expect(presenter.anchors.last == peek)
        tutorial.stop()
    }

    @Test func theBubbleUsesTheNotchsTheme() async {
        let registry = makeRegistry()
        let settings = registry.services.settings
        settings[CoreSettings.motion] = .calm
        settings[CoreSettings.textSize] = .large
        let presenter = RecordingTipPresenter()
        let tutorial = TutorialController(registry: registry, presenter: presenter)
        tutorial.start()
        #expect(presenter.themes.last?.motion == .calm)
        #expect(presenter.themes.last?.textSize == .large)
        settings[CoreSettings.motion] = .instant
        await settle { presenter.themes.last?.motion == .instant }
        #expect(presenter.themes.last?.motion == .instant)
        tutorial.stop()
    }

    @Test func aStepThatWaitsTooLongEndsTheTour() async {
        let registry = makeRegistry()
        let presenter = RecordingTipPresenter()
        let tutorial = TutorialController(registry: registry, presenter: presenter, idleLimit: .milliseconds(60))
        tutorial.start()
        await settle { !tutorial.isRunning }
        #expect(!tutorial.isRunning)
        #expect(!presenter.isVisible)
        #expect(!registry.services.settings[CoreSettings.tutorialCompleted])

        let progressing = TutorialController(registry: registry, presenter: presenter, celebration: .milliseconds(1),
                                             idleLimit: .milliseconds(600))
        progressing.start()
        try? await Task.sleep(for: .milliseconds(400))
        registry.testNotch?.emit(.opened(.hover))              // progress restarts the wait
        try? await Task.sleep(for: .milliseconds(400))
        #expect(progressing.isRunning)
        progressing.stop()
    }

    @Test func skipTourIsInThePaletteWhileTheTourRuns() throws {
        let registry = makeRegistry()
        let presenter = RecordingTipPresenter()
        let tutorial = TutorialController(registry: registry, presenter: presenter)
        let skip = TutorialController.skipTitle
        func commands(_ query: String) -> [PaletteCommand] {
            registry.commandProviders.flatMap { $0.commands(matching: query) }
        }
        #expect(commands("").isEmpty)                          // nothing while no tour runs
        tutorial.start()
        #expect(commands("").map(\.id) == ["onboarding.tutorial.skip"])
        #expect(commands(skip).map(\.title) == [skip])
        #expect(commands("zzz").isEmpty)
        let command = try #require(commands("").first)
        command.perform()
        #expect(!tutorial.isRunning)
        #expect(!presenter.isVisible)
        #expect(commands("").isEmpty)
    }
}

@MainActor @Test func theBubbleFollowsTheShapeWhenThePanelOpens() async throws {
    let registry = makeRegistry()
    let notch = try #require(registry.testNotch)
    let presenter = RecordingTipPresenter()
    let tutorial = TutorialController(registry: registry, presenter: presenter)
    tutorial.startForVisualQA(atStep: 4)                 // waiting for "pin, then Esc"
    #expect(presenter.anchors.last == TestNotch.closed)
    let open = CGRect(x: 800, y: 1264, width: 848, height: 170)
    notch.emit(.opened(.programmatic))
    notch.frame = open                                    // the shell writes the shape after emitting the event
    await settle { presenter.anchors.last == open }
    #expect(presenter.anchors.last == open)
    tutorial.stop()
}

@Suite struct TipConditionsTests {
    private let shape = CGRect(x: 663, y: 950, width: 185, height: 32)

    @Test func theTipShowsOnlyUnderAShownNotch() {
        #expect(TipConditions(shape: shape).anchor == shape)
        #expect(TipConditions(shape: nil).anchor == nil)
        #expect(TipConditions(shape: .zero).anchor == nil)                   // hidden phase: zero geometry
        #expect(TipConditions(shape: CGRect(x: 700, y: 982, width: 0, height: 0)).anchor == nil)
        #expect(TipConditions(shape: shape, isScreenLocked: true).anchor == nil)
        #expect(TipConditions(shape: shape, areDisplaysAsleep: true).anchor == nil)
        #expect(TipConditions(shape: shape, areLiveActivitiesPaused: true).anchor == nil)
        #expect(TipConditions(shape: shape, isFullScreenInFront: true).anchor == nil)
        #expect(TipConditions(shape: shape, isFullScreenInFront: true, showsOverFullScreen: true).anchor == shape)
    }
}

@Suite struct TipMarkTests {
    @Test func theMarkKeepsOneImageAndBouncesOnlyIntoDone() {
        #expect(TipContent.Mark.none.symbolName == nil)
        #expect(TipContent.Mark.symbol("keyboard").symbolName == "keyboard")
        #expect(TipContent.Mark.done.symbolName == "checkmark.circle.fill")
        #expect(TipContent.Mark.bounces(from: .symbol("keyboard"), to: .done, reduceMotion: false))
        #expect(!TipContent.Mark.bounces(from: .symbol("keyboard"), to: .done, reduceMotion: true))
        #expect(!TipContent.Mark.bounces(from: .done, to: .symbol("pin.fill"), reduceMotion: false))  // next step: no bounce
        #expect(!TipContent.Mark.bounces(from: .done, to: .done, reduceMotion: false))
    }
}

@MainActor @Suite struct OpenPromptTests {
    @Test func eachWayInGetsItsOwnSentence() {
        #expect(OpenPrompt(.hover, hasShortcut: true) == .rest(orPress: true))
        #expect(OpenPrompt(.hover, hasShortcut: false) == .rest(orPress: false))
        #expect(OpenPrompt(.click, hasShortcut: true) == .click(orPress: true))
        #expect(OpenPrompt(.click, hasShortcut: false) == .click(orPress: false))
        #expect(OpenPrompt(.shortcut, hasShortcut: true) == .press)
        #expect(OpenPrompt(.shortcut, hasShortcut: false) == .noShortcut)
        #expect(OpenPrompt.press.endsWithKeyCap && OpenPrompt.click(orPress: true).endsWithKeyCap)
        #expect(!OpenPrompt.noShortcut.endsWithKeyCap && !OpenPrompt.rest(orPress: false).endsWithKeyCap)
        let all: [OpenPrompt] = [.rest(orPress: true), .rest(orPress: false), .click(orPress: true), .click(orPress: false), .press]
        #expect(Set(all.map(\.tutorialText)).count == all.count)
        #expect(Set(all.map(\.coachText)).count == all.count)
        #expect(OpenPrompt.noShortcut.tutorialText == OpenPrompt.click(orPress: false).tutorialText)   // a click always opens
    }
}
