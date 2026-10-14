import CrannyCore
import Foundation
import Observation
import os
import Testing
@testable import CrannyTimer

/// VoiceOver: the face is one adjustable element in every state (the presets too), and the time left that the face
/// and the running activity speak follows the clock instead of the last render.
@MainActor @Suite struct TimerAccessibilityTests {
    @Test func theIdlePresetsAreAdjustableAndOfferEachPresetAsAnAction() {
        let h = TimerHarness()
        #expect(TimerFaceAccessibility.value(model: h.model, showsPresets: true) == TimerCopy.choosePreset)
        let actions = TimerFaceAccessibility.actions(model: h.model, showsPresets: true)
        // The set-up value (5 min) is a preset, so it is not offered twice.
        #expect(actions.map(\.id) == ["start.60", "start.300", "start.600", "start.1500"])
        #expect(actions.map(\.title) == [60, 300, 600, 1500].map { TimerCopy.startTitle(seconds: $0) })
        actions[2].perform()
        #expect(h.model.state.total == 600)
    }

    @Test func theLastDurationIsOfferedWhenItIsNotAPreset() {
        let h = TimerHarness()
        h.model.start(seconds: 90)
        h.model.stop()
        let actions = TimerFaceAccessibility.actions(model: h.model, showsPresets: true)
        #expect(actions.last?.id == "startSetup")
        #expect(actions.last?.title == TimerCopy.startTitle(seconds: 90))
        actions.last?.perform()
        #expect(h.model.state.total == 90)
    }

    @Test func adjustingThePresetsRevealsTheSetUpRing() {
        let h = TimerHarness()
        #expect(h.model.adjust(byMinutes: 1))                                   // what the adjustable action does
        #expect(h.model.draft == 360)                                           // draft != nil: the ring replaces the tiles
        #expect(TimerFaceAccessibility.value(model: h.model, showsPresets: false)
                == TimerCopy.setUp(TimerFormat.spoken(360)))
        let actions = TimerFaceAccessibility.actions(model: h.model, showsPresets: false)
        #expect(actions.map(\.id) == ["startSetup"])
        actions[0].perform()
        #expect(h.model.state.total == 360)
    }

    @Test func countingAndDoneActions() {
        let h = TimerHarness()
        h.model.start(seconds: 300)
        #expect(TimerFaceAccessibility.actions(model: h.model, showsPresets: false).map(\.id) == ["pause", "addMinute", "stop"])
        h.model.pause()
        #expect(TimerFaceAccessibility.actions(model: h.model, showsPresets: false).map(\.id) == ["resume", "addMinute", "stop"])
        h.model.stop()
        h.model.start(seconds: 5)
        h.scheduler.fire(advancing: h.clock)
        #expect(TimerFaceAccessibility.value(model: h.model, showsPresets: false) == TimerCopy.timerDone)
        #expect(TimerFaceAccessibility.actions(model: h.model, showsPresets: false).map(\.id) == ["addMinute", "stop"])
    }

    @Test func theSpokenTimeLeftFollowsTheClock() {
        let h = TimerHarness()
        h.model.start(seconds: 300)
        h.clock.advance(120)
        let expected = TimerCopy.left(TimerFormat.spoken(180), endingAt: TimerFormat.time(t0.addingTimeInterval(300)))
        #expect(TimerFaceAccessibility.value(model: h.model, showsPresets: false) == expected)
        #expect(TimerRunningActivity(model: h.model).accessibilityValue == TimerCopy.left(TimerFormat.spoken(180)))
        h.model.pause()
        h.clock.advance(500)
        #expect(TimerFaceAccessibility.value(model: h.model, showsPresets: false)
                == TimerCopy.pausedLeft(TimerFormat.spoken(180)))
    }

    @Test func aRefreshReRendersWhatReadsTheSpokenTime() {
        let h = TimerHarness()
        let activity = TimerRunningActivity(model: h.model)
        h.model.start(seconds: 300)
        h.model.refreshSpokenTime()

        let activityChanged = OSAllocatedUnfairLock(initialState: false)
        let faceChanged = OSAllocatedUnfairLock(initialState: false)
        withObservationTracking { _ = activity.accessibilityValue } onChange: { activityChanged.withLock { $0 = true } }
        withObservationTracking { _ = TimerFaceAccessibility.value(model: h.model, showsPresets: false) }
            onChange: { faceChanged.withLock { $0 = true } }

        h.clock.advance(0.5)
        h.model.refreshSpokenTime()                                             // same shown second: no update
        #expect(!activityChanged.withLock { $0 } && !faceChanged.withLock { $0 })
        h.clock.advance(1)
        h.model.refreshSpokenTime()                                             // the next second: both re-render
        #expect(activityChanged.withLock { $0 } && faceChanged.withLock { $0 })
        #expect(h.model.spokenSeconds == 299)
    }
}
