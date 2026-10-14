// CrannyEffects/EffectTiming.swift — time, pacing and easing shared by every effect (DESIGN.md §4.7, §5.3, §5.6).
// Effects are pure functions of time: these helpers turn a clock date into that time and pace the frames.
import CrannyCore
import Foundation

nonisolated enum EffectTiming {
    /// Seconds handed to the shaders: wall-clock seconds `mod 3600` (DESIGN.md §5.6 rule 3). Every path uses the
    /// same clock, so switching between the Metal layer, the SwiftUI shader and the fallback never jumps.
    static func ambientTime(_ date: Date) -> Double {
        date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3600)
    }

    /// The frame time an ambient effect draws: the resting frame under Reduce Motion (the light freezes on a
    /// designed frame, DESIGN.md §4.2), otherwise the clock's date, which `EffectClock` keeps while paused.
    static func ambientTime(_ date: Date, budget: EffectBudget, restingTime: Double) -> Double {
        budget.reduceMotion ? restingTime : ambientTime(date)
    }

    /// The frame interval of a one-shot moment: 1/30 s on AC, 1/20 s on battery, whether the panel is open or
    /// not, only for the moment's lifetime (DESIGN.md §5.6 rule 6).
    static func momentInterval(_ budget: EffectBudget) -> Double {
        budget.onBattery ? 1.0 / 20 : 1.0 / 30
    }

    /// The next frame deadline: one interval after the previous one, or one interval from now when frames were
    /// missed (sleep, a busy main thread), so a paced loop never fires a burst of catch-up frames.
    static func nextDeadline(after previous: ContinuousClock.Instant, now: ContinuousClock.Instant,
                             interval: Double) -> ContinuousClock.Instant {
        let next = previous.advanced(by: .seconds(interval))
        return next > now ? next : now.advanced(by: .seconds(interval))
    }
}

/// The song-change ripple (DESIGN.md §4.3, §5.6 `songRipple`): a 0.6-s radial wave from the camera, plus the
/// fallback's energy pulse that plays underneath on every path.
nonisolated enum Ripple {
    static let duration = 0.6
    static let amplitude: CGFloat = 6        // pt; also the distortion's maxSampleOffset
    static let wavelength: CGFloat = 56      // pt
    static let speed: CGFloat = 480          // pt/s

    /// Seconds since the trigger while the ripple plays, else nil.
    static func elapsed(since start: Date?, at date: Date) -> Double? {
        guard let start else { return nil }
        let t = date.timeIntervalSince(start)
        return t >= 0 && t < duration ? t : nil
    }

    /// The energy pulse: energy + 0.5 · (1 − t / 0.6)², capped at 1.5 so the light only lifts a little more.
    static func energy(_ energy: Double, elapsed t: Double?) -> Double {
        guard let t else { return energy }
        let k = 1 - t / duration
        return min(energy + 0.5 * k * k, 1.5)
    }
}

/// Easing curves for the moments (the shaders use the same formulas).
nonisolated enum Easing {
    static func clamped(_ t: Double) -> Double { min(max(t, 0), 1) }
    /// Cubic ease-out: fast start, gentle landing (first light's radius).
    static func easeOut(_ t: Double) -> Double { let u = 1 - clamped(t); return 1 - u * u * u }
    /// Smoothstep ease-in-out (the charge sweep's head).
    static func easeInOut(_ t: Double) -> Double { let u = clamped(t); return u * u * (3 - 2 * u) }
    /// GLSL/Metal `smoothstep`.
    static func smoothstep(_ edge0: Double, _ edge1: Double, _ x: Double) -> Double {
        guard edge1 != edge0 else { return x < edge0 ? 0 : 1 }
        return easeInOut((x - edge0) / (edge1 - edge0))
    }
}

/// Swift twin of `cranny::hash` (CrannyShaders.h): the Canvas fallbacks seed their particles exactly like the
/// shaders, so both paths draw the same motes and embers.
nonisolated enum StatelessHash {
    static func hash(_ seed: UInt32) -> Double {
        var n = seed
        n = (n << 13) ^ n
        n = n &* (n &* n &* 15731 &+ 789_221) &+ 1_376_312_589
        return Double(Float(n & 0x7fff_ffff) / Float(0x7fff_ffff))
    }
}
