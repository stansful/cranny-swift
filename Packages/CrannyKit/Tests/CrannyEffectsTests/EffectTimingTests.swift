import CrannyCore
import Foundation
import SwiftUI
import Testing
@testable import CrannyEffects

@Test func ambientTimeWrapsHourly() {
    let date = Date(timeIntervalSinceReferenceDate: 3600 * 5 + 12.5)
    #expect(abs(EffectTiming.ambientTime(date) - 12.5) < 1e-9)
    let running = EffectBudget(isOpen: true, onScreen: true, lowPower: false, fullScreenFront: false, reduceMotion: false, onBattery: false)
    var reduced = running
    reduced.reduceMotion = true
    #expect(abs(EffectTiming.ambientTime(date, budget: running, restingTime: 7.3) - 12.5) < 1e-9)
    #expect(EffectTiming.ambientTime(date, budget: reduced, restingTime: 7.3) == 7.3)   // Reduce Motion: the resting frame
}

@Test func momentsRunAtTheBudgetRateEvenWhenClosed() {
    let closed = EffectBudget(isOpen: false, onScreen: true, lowPower: false, fullScreenFront: false, reduceMotion: false, onBattery: false)
    var battery = closed
    battery.onBattery = true
    #expect(EffectTiming.momentInterval(closed) == 1.0 / 30)
    #expect(EffectTiming.momentInterval(battery) == 1.0 / 20)
}

@Test func pacingNeverCatchesUp() {
    let clock = ContinuousClock()
    let start = clock.now
    let next = FramePacing.nextDeadline(after: start, now: start, interval: 0.5)
    #expect(next == start.advanced(by: .seconds(0.5)))
    let late = start.advanced(by: .seconds(3))                         // three seconds of missed frames
    #expect(FramePacing.nextDeadline(after: start, now: late, interval: 0.5) == late.advanced(by: .seconds(0.5)))
}

/// Song change is "Colour only" under Calm and Reduce Motion (DESIGN.md §5.5), and Instant has no motion at all.
@Test func songRipplePlaysOnlyWhereMomentsPlay() {
    #expect(SongChangeRipple<Int>.plays(reduceMotion: false, motion: .standard))
    #expect(SongChangeRipple<Int>.plays(reduceMotion: false, motion: .lively))
    #expect(!SongChangeRipple<Int>.plays(reduceMotion: false, motion: .calm))
    #expect(!SongChangeRipple<Int>.plays(reduceMotion: false, motion: .instant))
    #expect(!SongChangeRipple<Int>.plays(reduceMotion: true, motion: .standard))
}

@Test func rippleWindowAndEnergyPulse() {
    let start = Date(timeIntervalSinceReferenceDate: 100)
    #expect(Ripple.elapsed(since: nil, at: start) == nil)
    #expect(Ripple.elapsed(since: start, at: start.addingTimeInterval(-0.1)) == nil)
    #expect(abs((Ripple.elapsed(since: start, at: start.addingTimeInterval(0.3)) ?? -1) - 0.3) < 1e-6)
    #expect(Ripple.elapsed(since: start, at: start.addingTimeInterval(0.61)) == nil)  // over after 0.6 s
    #expect(Ripple.energy(0.2, elapsed: nil) == 0.2)
    #expect(abs(Ripple.energy(0.2, elapsed: 0) - 0.7) < 1e-9)          // + 0.5 · (1 − t/0.6)²
    #expect(abs(Ripple.energy(0.2, elapsed: 0.3) - 0.325) < 1e-9)
    #expect(Ripple.energy(1, elapsed: 0) == 1.5)                        // capped
}

@Test func easingCurves() {
    #expect(Easing.easeOut(0) == 0 && Easing.easeOut(1) == 1 && Easing.easeOut(0.5) == 0.875)
    #expect(Easing.easeInOut(0) == 0 && Easing.easeInOut(1) == 1 && Easing.easeInOut(0.5) == 0.5)
    #expect(Easing.smoothstep(0.4, 0.6, 0.3) == 0 && Easing.smoothstep(0.4, 0.6, 0.7) == 1)
    #expect(Easing.smoothstep(1, 1, 0.5) == 0 && Easing.smoothstep(1, 1, 1.5) == 1)   // degenerate edges
    #expect(Easing.clamped(-2) == 0 && Easing.clamped(2) == 1)
}

/// The Swift twin of `cranny::hash` must give the shader's values, or the Canvas fallbacks draw other particles.
@Test func statelessHashMatchesTheShader() {
    // n = 0: ((0 << 13) ^ 0) · (…) + 1376312589 = 1376312589, masked to 31 bits, over 0x7fffffff.
    #expect(StatelessHash.hash(0) == Double(Float(1_376_312_589) / Float(0x7fff_ffff)))
    let values = (0..<500).map { StatelessHash.hash(UInt32($0)) }
    #expect(values.allSatisfy { (0...1).contains($0) })
    #expect(Set(values).count > 490)                                     // no obvious collisions
    #expect(values == (0..<500).map { StatelessHash.hash(UInt32($0)) })  // deterministic
    let mean = values.reduce(0, +) / Double(values.count)
    #expect(abs(mean - 0.5) < 0.05)
}

@Test func momentClockClampsElapsedTime() {
    let start = Date(timeIntervalSinceReferenceDate: 50)
    #expect(MomentClock<EmptyView>.elapsed(from: start, to: start.addingTimeInterval(-1), duration: 0.9) == 0)
    #expect(abs(MomentClock<EmptyView>.elapsed(from: start, to: start.addingTimeInterval(0.4), duration: 0.9) - 0.4) < 1e-6)
    #expect(MomentClock<EmptyView>.elapsed(from: start, to: start.addingTimeInterval(5), duration: 0.9) == 0.9)
}
