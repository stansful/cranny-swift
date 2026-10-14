import CrannyCore
import Foundation
import Testing
@testable import CrannyTimer

@MainActor @Suite struct TimerModelTests {
    @Test func startSchedulesOneWakeUpAtTheLastMinute() {
        let h = TimerHarness()
        h.model.start(seconds: 300)
        #expect(h.model.state.isRunning)
        #expect(h.model.lastDuration == 300)
        #expect(h.model.runningRevision == 1)
        #expect(h.scheduler.date == t0.addingTimeInterval(240))
    }

    @Test func lastMinuteBumpsTheRevisionAndPeeksWhenTheOptionIsOn() {
        let h = TimerHarness()
        h.model.start(seconds: 300)
        h.scheduler.fire(advancing: h.clock)
        #expect(h.model.runningRevision == 2)
        #expect(h.peekLog.values == [.timerRunning])
        #expect(h.scheduler.date == t0.addingTimeInterval(300))                 // next: the deadline
    }

    @Test func noPeekWhenTheOptionIsOff() {
        let h = TimerHarness()
        h.services.settings[TimerSettings.peeksAtOneMinute] = false
        h.model.start(seconds: 300)
        h.scheduler.fire(advancing: h.clock)
        #expect(h.model.runningRevision == 2)                                   // still undoes a dismissal
        #expect(h.peekLog.values.isEmpty)
    }

    @Test func aShortTimerHasNoLastMinuteMoment() {
        let h = TimerHarness()
        h.model.start(seconds: 45)
        #expect(h.scheduler.date == t0.addingTimeInterval(45))
        h.scheduler.fire(advancing: h.clock)
        #expect(h.peekLog.values.isEmpty)
        #expect(h.model.state.isDone)
    }

    @Test func finishPlaysTheChosenSoundOnceAndExpiresAfterAMinute() {
        let h = TimerHarness()
        h.services.settings[TimerSettings.sound] = "Ping"
        h.model.start(seconds: 30)
        h.scheduler.fire(advancing: h.clock)
        #expect(h.model.state.phase == .done(at: t0.addingTimeInterval(30)))
        #expect(h.model.doneRevision == 1)
        #expect(h.sound.played == ["Ping"])
        #expect(h.scheduler.date == t0.addingTimeInterval(90))
        h.scheduler.fire(advancing: h.clock)
        #expect(h.model.state.phase == .idle)
        #expect(h.scheduler.date == nil)                                        // idle: nothing scheduled
    }

    @Test func demoModeAndNoSoundStaySilent() {
        let h = TimerHarness()
        h.demo.isOn = true
        h.model.start(seconds: 10)
        h.scheduler.fire(advancing: h.clock)
        #expect(h.model.state.isDone)
        #expect(h.sound.played.isEmpty)

        let quiet = TimerHarness()
        quiet.services.settings[TimerSettings.sound] = nil
        quiet.model.start(seconds: 10)
        quiet.scheduler.fire(advancing: quiet.clock)
        #expect(quiet.model.doneRevision == 1)
        #expect(quiet.sound.played.isEmpty)
    }

    @Test func aDeadlineMissedByMoreThanAMinuteEndsSilently() {
        let h = TimerHarness()
        h.model.start(seconds: 30)
        h.clock.advance(3600)                                                   // the Mac slept for an hour
        h.model.reconcile()
        #expect(h.model.state.phase == .idle)
        #expect(h.model.doneRevision == 0)
        #expect(h.sound.played.isEmpty)
        #expect(h.peekLog.values.isEmpty)
    }

    @Test func wakingShortlyAfterTheDeadlineStillAlertsButSkipsTheMissedPeek() {
        let h = TimerHarness()
        h.model.start(seconds: 300)
        h.clock.advance(310)                                                    // slept through the last minute
        h.model.reconcile()
        #expect(h.model.state.isDone)
        #expect(h.model.doneRevision == 1)
        #expect(h.peekLog.values.isEmpty)
        #expect(h.sound.played == ["Glass"])
    }

    @Test func pauseCancelsTheWakeUpAndResumeReschedulesIt() {
        let h = TimerHarness()
        h.model.start(seconds: 300)
        h.clock.advance(100)
        h.model.togglePause()
        #expect(h.model.state.phase == .paused(remaining: 200))
        #expect(h.scheduler.date == nil)
        h.clock.advance(1000)
        h.model.togglePause()
        #expect(h.model.state.endDate == h.clock.now.addingTimeInterval(200))
        #expect(h.scheduler.date == h.clock.now.addingTimeInterval(140))          // its last minute
    }

    @Test func stopSilencesAndClears() {
        let h = TimerHarness()
        h.model.start(seconds: 5)
        h.scheduler.fire(advancing: h.clock)
        let stopsBefore = h.sound.stops
        h.model.stop()
        #expect(h.model.state.phase == .idle)
        #expect(h.sound.stops == stopsBefore + 1)
        #expect(h.scheduler.date == nil)
    }

    @Test func addMinuteRearmsTheLastMinuteAndRestartsWhenDone() {
        let h = TimerHarness()
        h.model.start(seconds: 120)
        h.scheduler.fire(advancing: h.clock)                                    // last minute (t0 + 60)
        #expect(h.model.runningRevision == 2)
        h.model.addMinute()                                                     // 60 → 120 s left
        #expect(h.scheduler.date == h.clock.now.addingTimeInterval(60))         // a new last-minute moment
        h.scheduler.fire(advancing: h.clock)
        #expect(h.model.runningRevision == 3)
        h.scheduler.fire(advancing: h.clock)                                    // done
        #expect(h.model.state.isDone)
        h.model.addMinute()
        #expect(h.model.state.isRunning)
        #expect(h.model.state.total == 60)
    }

    @Test func adjustChangesARunningTimerOrTheIdleSetUp() {
        let h = TimerHarness()
        #expect(h.model.setupDuration == 300)
        #expect(h.model.adjust(byMinutes: 2))
        #expect(h.model.draft == 420)
        #expect(h.model.adjust(byMinutes: -10))
        #expect(h.model.draft == 60)                                            // never below one minute
        #expect(!h.model.adjust(byMinutes: -1))
        h.model.startSetup()
        #expect(h.model.state.total == 60)
        #expect(h.model.draft == nil)
        #expect(h.model.adjust(byMinutes: 1))
        #expect(h.model.state.remaining(at: h.clock.now) == 120)
        #expect(!h.model.adjust(byMinutes: 0))
    }

    @Test func turningDownASetUpBelowOneMinuteNeverRaisesIt() {
        let h = TimerHarness()
        h.model.start(seconds: 30)
        h.model.stop()
        #expect(h.model.setupDuration == 30)
        #expect(!h.model.adjust(byMinutes: -1))                                 // no change, so no detent haptic
        #expect(h.model.draft == nil)
        #expect(h.model.setupDuration == 30)
        #expect(h.model.adjust(byMinutes: 1))
        #expect(h.model.draft == 90)
        #expect(h.model.adjust(byMinutes: -1))                                  // 90 → 60: still a decrease
        #expect(h.model.draft == 60)
        #expect(!h.model.adjust(byMinutes: -1))
    }

    @Test func turningUpAtTheMaximumIsRefused() {
        let h = TimerHarness()
        h.model.start(seconds: Int(TimerLimits.maximum))
        h.model.stop()
        #expect(!h.model.adjust(byMinutes: 1))
        #expect(h.model.adjust(byMinutes: -1))
        #expect(h.model.draft == Int(TimerLimits.maximum) - 60)
    }

    @Test func startUsesTheLastDurationAndPresetsAreSanitised() {
        let h = TimerHarness()
        h.services.settings[TimerSettings.presets] = [0, 90, -5, 600, 1500, 3000, 99_999_999]
        #expect(h.model.presets == [90, 600, 1500, 3000])
        h.model.start(seconds: 90)
        h.model.stop()
        #expect(h.model.setupDuration == 90)
    }

    @Test func persistsEveryChangeAndRestoresARunningTimer() async throws {
        let url = temporaryFile()
        let h = TimerHarness(file: TimerStateFile(url: url))
        h.model.start(seconds: 600)
        h.clock.advance(100)
        h.model.persistNow()
        let saved = try #require(TimerStateFile(url: url).load())
        #expect(saved.state.endDate == t0.addingTimeInterval(600))
        #expect(saved.lastDuration == 600)

        let relaunched = TimerHarness(file: TimerStateFile(url: url))
        relaunched.clock.now = t0.addingTimeInterval(200)
        await relaunched.model.restore()
        #expect(relaunched.model.state.endDate == t0.addingTimeInterval(600))
        #expect(relaunched.model.lastDuration == 600)
        #expect(relaunched.scheduler.date == t0.addingTimeInterval(540))
    }

    @Test func restoreAfterTheDeadlineShowsDoneWithoutSound() async throws {
        let url = temporaryFile()
        try TimerStateFile(url: url).write(TimerSnapshot(state: TimerState(phase: .running(endDate: t0.addingTimeInterval(-20)), total: 300),
                                                         lastDuration: 300), sequence: 1)
        let h = TimerHarness(file: TimerStateFile(url: url))
        await h.model.restore()
        #expect(h.model.state.phase == .done(at: t0.addingTimeInterval(-20)))
        #expect(h.model.doneRevision == 1)
        #expect(h.sound.played.isEmpty)
        #expect(h.scheduler.date == t0.addingTimeInterval(40))                  // done expires a minute after the end
    }

    @Test func aQuitBeforeTheRestoreFinishedKeepsTheSavedTimer() async throws {
        let url = temporaryFile()
        let saved = TimerSnapshot(state: TimerState(phase: .running(endDate: t0.addingTimeInterval(300)), total: 600),
                                  lastDuration: 600)
        try TimerStateFile(url: url).write(saved, sequence: 1)
        let h = TimerHarness(file: TimerStateFile(url: url))
        h.model.persistNow()                                    // the terminate hook, before the launch hook restored
        #expect(TimerStateFile(url: url).load() == saved)
        await h.model.restore()
        #expect(h.model.state.endDate == t0.addingTimeInterval(300))
    }

    @Test func aChangeMadeBeforeTheRestoreFinishesWins() async throws {
        let url = temporaryFile()
        try TimerStateFile(url: url).write(TimerSnapshot(state: TimerState(phase: .paused(remaining: 50), total: 60),
                                                         lastDuration: 60), sequence: 1)
        let h = TimerHarness(file: TimerStateFile(url: url))
        h.model.start(seconds: 1500)
        await h.model.restore()
        #expect(h.model.state.total == 1500)
    }

    @Test func samplesShowTheirState() {
        let running = TimerModel.sample(.running(left: 272, total: 300))
        #expect(running.state.isRunning)
        #expect(running.state.displayedSeconds(at: running.now) <= 272)
        let done = TimerModel.sample(.done(total: 300))
        #expect(done.state.isDone)
        #expect(done.doneRevision == 1)
        let setup = TimerModel.sample(.setup(seconds: 360))
        #expect(setup.setupDuration == 360)
    }

    @Test func samplesNeverPersistOrPlaySounds() throws {
        // A sample whose deadline has just passed: reconciling finishes it as a real run would.
        let sample = TimerModel.sample(.running(left: -1, total: 60))
        #expect(sample.dependencies.file == nil)                                // nothing is read or written
        #expect(sample.dependencies.isDemoMode())                               // the done sound is muted
        let sound = try #require(sample.dependencies.sound as? SilentTimerSound)
        sample.reconcile()
        #expect(sample.state.isDone)
        #expect(sample.doneRevision == 1)                                       // the "Timer done" activity would show
        #expect(sound.played.isEmpty)
    }

    @Test func aSampleModelLeavesNoWakeUpBehind() throws {
        var model: TimerModel? = .sample(.running(left: 272, total: 300))      // its last minute is 212 s away
        weak let scheduler = model?.dependencies.scheduler as? SleepingWakeScheduler
        let task = try #require(scheduler?.task)
        #expect(!task.isCancelled)
        model = nil
        #expect(scheduler == nil)
        #expect(task.isCancelled)
    }

    @Test func aSchedulerCancelsItsPendingWakeUpWhenItGoesAway() throws {
        var scheduler: SleepingWakeScheduler? = SleepingWakeScheduler()
        scheduler?.schedule(at: Date().addingTimeInterval(3600)) {}
        let task = try #require(scheduler?.task)
        scheduler = nil
        #expect(task.isCancelled)
    }
}
