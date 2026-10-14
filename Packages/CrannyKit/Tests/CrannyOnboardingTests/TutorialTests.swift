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

        let notch = try #require(registry.previewNotch)
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
        let notch = try #require(registry.previewNotch)
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
        registry.previewNotch?.emit(.opened(.hover))
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
        tutorial.stop()
    }
}

/// A notch whose shape frame the test moves, as the shell's does when the panel opens.
@MainActor private final class MovingNotch: NotchControl {
    var frame: CGRect? = CGRect(x: 1000, y: 1431, width: 64, height: 5)
    private var observers: [UUID: @MainActor (NotchEvent) -> Void] = [:]
    func open(page: PageID?, focus: WidgetID?, reason: OpenReason) {}
    func close() {}
    func togglePinned() {}
    func setHoldOpen(_ hold: Bool, reason: String) {}
    func setFocusMode(_ widget: WidgetID?) {}
    func requestPeek(_ activity: ActivityID) {}
    func requestKeyboardFocus() {}
    func setCalibrationOverlay(_ visible: Bool) {}
    func shapeFrameOnScreen() -> CGRect? { frame }
    func presentAirDrop(_ urls: [URL]) async -> Bool { false }
    func presentSharePicker(_ urls: [URL]) {}
    func flash(symbol: String, label: String) {}
    func addEventObserver(_ handler: @escaping @MainActor (NotchEvent) -> Void) -> UUID {
        let id = UUID(); observers[id] = handler; return id
    }
    func removeEventObserver(_ id: UUID) { observers[id] = nil }
    func emit(_ event: NotchEvent) { for observer in observers.values { observer(event) } }
}

@MainActor @Test func theBubbleFollowsTheShapeWhenThePanelOpens() async {
    let notch = MovingNotch()
    let defaults = UserDefaults(suiteName: "cranny.test.\(UUID().uuidString)") ?? .standard
    let services = CrannyServices(settings: SettingsStore(defaults: defaults), permissions: PermissionsCenter(),
                                  haptics: Haptics(isEnabled: { false }), paths: .temporary(), notch: notch,
                                  environment: PreviewSystemEnvironment(), app: PreviewAppControl())
    let presenter = RecordingTipPresenter()
    let tutorial = TutorialController(registry: ModuleRegistry(services: services), presenter: presenter)
    tutorial.startForVisualQA(atStep: 4)                 // waiting for "pin, then Esc"
    #expect(presenter.anchors.last == notch.frame)
    let open = CGRect(x: 800, y: 1264, width: 848, height: 170)
    notch.emit(.opened(.programmatic))
    notch.frame = open                                    // the shell writes the shape after emitting the event
    await settle { presenter.anchors.last == open }
    #expect(presenter.anchors.last == open)
    tutorial.stop()
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
