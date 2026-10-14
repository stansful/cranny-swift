import Foundation
import Testing
@testable import CrannyTimer

@Suite struct TimerStateTests {
    @Test func startCountsDownFromTheDeadline() {
        var s = TimerState()
        s.start(duration: 300, now: t0)
        #expect(s.endDate == t0.addingTimeInterval(300))
        #expect(s.total == 300)
        #expect(s.remaining(at: t0.addingTimeInterval(100)) == 200)
        #expect(s.progress(at: t0.addingTimeInterval(150)) == 0.5)
        #expect(s.remaining(at: t0.addingTimeInterval(400)) == 0)
    }

    @Test func displayedSecondsRoundUpSoTheDisplayReachesZeroAtTheDeadline() {
        var s = TimerState()
        s.start(duration: 300, now: t0)
        #expect(s.displayedSeconds(at: t0) == 300)                              // "5:00", not "4:59"
        #expect(s.displayedSeconds(at: t0.addingTimeInterval(0.01)) == 300)
        #expect(s.displayedSeconds(at: t0.addingTimeInterval(1)) == 299)
        #expect(s.displayedSeconds(at: t0.addingTimeInterval(299.5)) == 1)
        #expect(s.displayedSeconds(at: t0.addingTimeInterval(300)) == 0)
    }

    @Test func durationsAreClampedAndRounded() {
        var s = TimerState()
        s.start(duration: 0, now: t0)
        #expect(s.total == TimerLimits.minimum)
        s.start(duration: 100_000, now: t0)
        #expect(s.total == TimerLimits.maximum)
        s.start(duration: 89.6, now: t0)
        #expect(s.total == 90)
    }

    @Test func pauseFreezesAndResumeShiftsTheDeadline() {
        var s = TimerState()
        s.start(duration: 300, now: t0)
        let r1 = s.pause(now: t0.addingTimeInterval(100))
        #expect(r1)
        #expect(s.phase == .paused(remaining: 200))
        #expect(s.remaining(at: t0.addingTimeInterval(10_000)) == 200)
        let r2 = s.pause(now: t0)
        #expect(!r2)                                              // already paused
        let r3 = s.resume(now: t0.addingTimeInterval(1000))
        #expect(r3)
        #expect(s.endDate == t0.addingTimeInterval(1200))
        #expect(s.total == 300)
        let r4 = s.resume(now: t0)
        #expect(!r4)
    }

    @Test func pausingAfterTheDeadlineIsRefused() {
        var s = TimerState()
        s.start(duration: 60, now: t0)
        let r5 = s.pause(now: t0.addingTimeInterval(60))
        #expect(!r5)
        #expect(s.isRunning)
    }

    @Test func addMinuteGrowsTimeLeftAndTotal() {
        var s = TimerState()
        s.start(duration: 300, now: t0)
        let r6 = s.addTime(60, now: t0.addingTimeInterval(240))
        #expect(r6)                  // 60 s left → 120 s
        #expect(s.remaining(at: t0.addingTimeInterval(240)) == 120)
        #expect(s.total == 360)
        #expect(s.progress(at: t0.addingTimeInterval(240)) == 120.0 / 360)
    }

    @Test func addMinuteWhenDoneStartsAOneMinuteTimer() {
        var s = TimerState(phase: .done(at: t0), total: 300)
        let r7 = s.addTime(60, now: t0.addingTimeInterval(5))
        #expect(r7)
        #expect(s.endDate == t0.addingTimeInterval(65))
        #expect(s.total == 60)
        var idle = TimerState()
        let r8 = idle.addTime(60, now: t0)
        #expect(!r8)
    }

    @Test func adjustRefusesToGoBelowOneSecondAndClampsAtTheMaximum() {
        var s = TimerState()
        s.start(duration: 90, now: t0)
        let r9 = s.adjust(by: -60, now: t0)
        #expect(r9)                                     // 90 → 30
        #expect(s.remaining(at: t0) == 30)
        #expect(s.total == 30)
        let r10 = s.adjust(by: -60, now: t0)
        #expect(!r10)                                    // would be negative
        #expect(s.remaining(at: t0) == 30)
        s.start(duration: TimerLimits.maximum - 30, now: t0)
        let r11 = s.adjust(by: 60, now: t0)
        #expect(r11)
        #expect(s.remaining(at: t0) == TimerLimits.maximum)
        let r12 = s.adjust(by: 60, now: t0)
        #expect(!r12)                                     // nothing changes any more
    }

    @Test func adjustWorksWhilePausedAndNeverWhenIdleOrDone() {
        var s = TimerState(phase: .paused(remaining: 200), total: 300)
        let r13 = s.adjust(by: 60, now: t0)
        #expect(r13)
        #expect(s.phase == .paused(remaining: 260))
        #expect(s.total == 360)                                                 // the total grows with the time added
        var idle = TimerState()
        let r14 = idle.adjust(by: 60, now: t0)
        #expect(!r14)
        var done = TimerState(phase: .done(at: t0), total: 60)
        let r15 = done.adjust(by: 60, now: t0)
        #expect(!r15)
    }

    @Test func finishAndExpire() {
        var s = TimerState()
        s.start(duration: 60, now: t0)
        let r16 = s.finish()
        #expect(r16)
        #expect(s.phase == .done(at: t0.addingTimeInterval(60)))
        #expect(s.progress(at: t0) == 1)                                        // a done ring is full
        let r17 = s.finish()
        #expect(!r17)
        let r18 = s.expire()
        #expect(r18)
        #expect(s.phase == .idle)
        #expect(s.total == 0)
        let r19 = s.expire()
        #expect(!r19)
    }

    @Test func lastMinuteAndPulseWindow() {
        var s = TimerState()
        s.start(duration: 300, now: t0)
        #expect(!s.isInLastMinute(at: t0.addingTimeInterval(239)))
        #expect(s.isInLastMinute(at: t0.addingTimeInterval(240)))
        #expect(!s.isInPulseWindow(at: t0.addingTimeInterval(289)))
        #expect(s.isInPulseWindow(at: t0.addingTimeInterval(290)))
        #expect(!s.isInPulseWindow(at: t0.addingTimeInterval(300)))             // at zero: no pulse
        s.pause(now: t0.addingTimeInterval(295))
        #expect(!s.isInPulseWindow(at: t0.addingTimeInterval(295)))             // paused digits never pulse
    }

    @Test(arguments: [
        (TimerPhase.running(endDate: t0.addingTimeInterval(10)), TimerPhase.running(endDate: t0.addingTimeInterval(10))),
        (.running(endDate: t0.addingTimeInterval(-30)), .done(at: t0.addingTimeInterval(-30))),   // ended 30 s ago
        (.running(endDate: t0.addingTimeInterval(-60)), .idle),                                    // a minute ago
        (.running(endDate: t0.addingTimeInterval(-86_400)), .idle),
        (.done(at: t0.addingTimeInterval(-59)), .done(at: t0.addingTimeInterval(-59))),
        (.done(at: t0.addingTimeInterval(-61)), .idle),
        (.paused(remaining: 42), .paused(remaining: 42)),
        (.paused(remaining: 0), .idle),
        (.idle, .idle),
    ])
    func reconciledAtLaunch(_ saved: TimerPhase, _ expected: TimerPhase) {
        #expect(TimerState(phase: saved, total: 100).reconciled(at: t0).phase == expected)
    }

    @Test func codableRoundTrip() throws {
        for phase in [TimerPhase.idle, .running(endDate: t0), .paused(remaining: 12.5), .done(at: t0)] {
            let s = TimerState(phase: phase, total: 99)
            let data = try JSONEncoder().encode(s)
            #expect(try JSONDecoder().decode(TimerState.self, from: data) == s)
        }
    }
}
