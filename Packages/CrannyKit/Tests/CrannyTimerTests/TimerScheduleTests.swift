import CoreGraphics
import Foundation
import Testing
@testable import CrannyTimer

@Suite struct TimerScheduleTests {
    @Test func aRunWakesAtTheLastMinuteThenAtTheDeadline() throws {
        var s = TimerState()
        s.start(duration: 300, now: t0)
        let first = try #require(TimerSchedule.next(for: s, lastMinuteSignalled: false))
        #expect(first.event == .lastMinute)
        #expect(first.date == t0.addingTimeInterval(240))
        let second = try #require(TimerSchedule.next(for: s, lastMinuteSignalled: true))
        #expect(second.event == .finish)
        #expect(second.date == t0.addingTimeInterval(300))
    }

    @Test func doneWakesOnceToExpireAndIdleOrPausedNeverWake() throws {
        let done = try #require(TimerSchedule.next(for: TimerState(phase: .done(at: t0), total: 60), lastMinuteSignalled: true))
        #expect(done.event == .expire)
        #expect(done.date == t0.addingTimeInterval(TimerLimits.doneLinger))
        #expect(TimerSchedule.next(for: TimerState(), lastMinuteSignalled: false) == nil)
        #expect(TimerSchedule.next(for: TimerState(phase: .paused(remaining: 30), total: 60), lastMinuteSignalled: false) == nil)
    }

    @Test func aRunStartingInsideItsLastMinuteHasNoLastMinuteMoment() {
        #expect(!TimerSchedule.lastMinuteIsAhead(remaining: 60))
        #expect(!TimerSchedule.lastMinuteIsAhead(remaining: 30))
        #expect(TimerSchedule.lastMinuteIsAhead(remaining: 61))
    }
}

@Suite struct TimerClockTests {
    @Test func countdownTicksExactlyWhenTheShownSecondChanges() throws {
        let deadline = t0.addingTimeInterval(300)
        // 300 s left ("5:00") → the next change ("4:59") is at t0 + 1.
        let a = try #require(CountdownTick.next(after: t0, deadline: deadline))
        #expect(abs(a.timeIntervalSince(t0) - (1 + CountdownTick.margin)) < 1e-6)
        // 4.3 s left (shows "0:05") → next change at deadline − 4.
        let b = try #require(CountdownTick.next(after: deadline.addingTimeInterval(-4.3), deadline: deadline))
        #expect(abs(b.timeIntervalSince(deadline) - (-4 + CountdownTick.margin)) < 1e-6)
        // 0.4 s left ("0:01") → wakes just after the deadline to draw "0:00", then never again.
        let c = try #require(CountdownTick.next(after: deadline.addingTimeInterval(-0.4), deadline: deadline))
        #expect(c > deadline)
        #expect(CountdownTick.next(after: deadline, deadline: deadline) == nil)
        #expect(CountdownTick.next(after: deadline.addingTimeInterval(1), deadline: deadline) == nil)
    }

    @Test func aCountdownWakesOncePerSecond() {
        let deadline = t0.addingTimeInterval(10)
        var now = t0, wakes = 0
        while let next = CountdownTick.next(after: now, deadline: deadline) {
            #expect(next > now)
            now = next
            wakes += 1
        }
        #expect(wakes == 10)
    }

    @Test func ringCadenceFollowsOnePixelOfArc() {
        // Widget ring (88 pt @2x): a 5-minute timer redraws about twice a second, a 25-minute one once per 2.7 s.
        let five = RingCadence.interval(total: 300, diameter: 88, displayScale: 2)
        #expect(five > 0.5 && five < 0.6)
        #expect(abs(RingCadence.interval(total: 1500, diameter: 88, displayScale: 2) - 1500 / (Double.pi * 176)) < 1e-9)
        // Never faster than 4 fps (a 1-minute timer would want ≈ 9), never slower than every 30 s.
        #expect(RingCadence.interval(total: 60, diameter: 88, displayScale: 2) == RingCadence.fastest)
        #expect(RingCadence.interval(total: 1, diameter: 88, displayScale: 2) == RingCadence.fastest)
        #expect(RingCadence.interval(total: 86_000, diameter: 16, displayScale: 2) == RingCadence.slowest)
    }

    @Test func pulseTriggerChangesOnlyInsideTheWindowAndNotAtZero() {
        let triggers = (0...12).reversed().map { seconds in
            TimerDigits.pulseTrigger(seconds: seconds, pulsing: seconds <= 10 && seconds > 0)
        }
        // 12, 11 → constant; 10 … 1 → one change per second; 0 → same as at 1 (no 11th pulse).
        let changes = zip(triggers, triggers.dropFirst()).filter { $0 != $1 }.count
        #expect(changes == 10)
        #expect(triggers.last == triggers[triggers.count - 2])
    }

    /// Pulses a viewer sees across renders: the trigger changed and the new render scales up.
    private func visiblePulses(_ renders: [(state: TimerState, now: Date)]) -> Int {
        var count = 0
        var previous: Int?
        for render in renders {
            let seconds = render.state.displayedSeconds(at: render.now)
            let pulsing = render.state.isInPulseWindow(at: render.now)
            let trigger = TimerDigits.pulseTrigger(seconds: seconds, pulsing: pulsing)
            if let previous, previous != trigger, TimerDigits.pulseScale(up: true, pulsing: pulsing, animates: true) > 1 {
                count += 1
            }
            previous = trigger
        }
        return count
    }

    @Test func leavingThePulseWindowEarlyPlaysNoExtraPulse() {
        var running = TimerState()
        running.start(duration: 60, now: t0)
        let shows7 = t0.addingTimeInterval(53.5)                                // 6.5 s left
        var paused = running
        paused.pause(now: shows7)
        var longer = paused
        longer.adjust(by: 60, now: shows7)
        let pauseThenAdd = [(running, t0.addingTimeInterval(52.5)), (running, shows7),   // "0:08" → "0:07": a pulse
                            (paused, shows7), (paused, shows7.addingTimeInterval(5)),    // paused in the window
                            (longer, shows7.addingTimeInterval(5))]                      // +1 min while paused
        #expect(visiblePulses(pauseThenAdd.map { (state: $0.0, now: $0.1) }) == 1)

        var added = running
        added.addTime(60, now: shows7)                                          // +1 min while pulsing
        #expect(visiblePulses([(running, shows7), (added, shows7)].map { (state: $0.0, now: $0.1) }) == 0)
        #expect(TimerDigits.pulseScale(up: true, pulsing: true, animates: false) == 1)   // Calm, Instant, Reduce Motion
        #expect(TimerDigits.pulseScale(up: false, pulsing: true, animates: true) == 1)
    }
}

@Suite struct ScrollDetentsTests {
    @Test func fingersUpAddMinutesFingersDownRemoveThem() {
        var d = ScrollDetents(step: 12)
        let r1 = d.update(translation: -5)
        #expect(r1 == 0)
        let r2 = d.update(translation: -12)
        #expect(r2 == 1)
        let r3 = d.update(translation: -30)
        #expect(r3 == 1)
        let r4 = d.update(translation: -36)
        #expect(r4 == 1)
        let r5 = d.update(translation: -10)
        #expect(r5 == -3)                               // back down past three detents
        let r6 = d.update(translation: 25)
        #expect(r6 == -2)
        d.reset()
        let r7 = d.update(translation: 0)
        #expect(r7 == 0)
        let r8 = d.update(translation: -60)
        #expect(r8 == 5)                                // a fast swipe: several at once
    }

    @Test func stepIsNeverZero() {
        var d = ScrollDetents(step: 0)
        #expect(d.step == 1)
        let r9 = d.update(translation: -3)
        #expect(r9 == 3)
    }
}
