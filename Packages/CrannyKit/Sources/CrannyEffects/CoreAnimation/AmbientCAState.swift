// CrannyEffects/CoreAnimation/AmbientCAState.swift — what the Core Animation light draws (Appearance ▸ Quality ▸
// Efficient, DESIGN.md §5.7), the cross-fade it uses for palette, level and effect changes, and its clock.
//
// The clock: every looping animation of the light starts at `AmbientCAClock.epoch` in the local time of one layer, the
// clock layer. Its local time is `epoch` + the light's time in seconds. Running, the clock layer follows the media
// clock (speed 1); paused (closed, occluded, full screen) it stands at the time it reached (speed 0, `timeOffset`);
// resting (Reduce Motion, Motion ▸ Instant) it stands at `restingTime`. A resumed clock continues from where it stopped,
// so nothing jumps, and a stopped clock costs the window server nothing: no animation of the light advances.
import CrannyCore
import Foundation
import QuartzCore

/// Everything the Core Animation light needs; SwiftUI hands a new value to the view on every update, and the view
/// changes only what differs.
nonisolated struct AmbientCAState: Equatable, Sendable {
    var effect: AmbientEffect
    var glows: [RGB]
    var level: AmbienceLevel
    /// 0…1: how far the light has risen from the bottom edge (`ambientIn` / `ambientOut`, AmbientLayer).
    var fill: Double
    /// `EffectBudget.minimumInterval`: the frame interval (30 fps on AC, 20 on battery), or nil while paused.
    var interval: Double?
    /// Reduce Motion or Motion ▸ Instant (`EffectBudget.reduceMotion`): the light stands still on `restingTime`, and the
    /// fill fades instead of rising.
    var rests: Bool
    /// The light's time (seconds) of the frame the resting light shows.
    var restingTime: Double
    /// Where the halo blooms.
    var halo: HaloPlacement
    /// The last song change (`songChangeRipple`): a new date lifts the light once (`AmbientCASwell`).
    var rippleStart: Date?
    /// How palette, level and effect changes cross-fade (`colorShift`); nil: at once (Motion ▸ Instant).
    var crossFade: AmbientCAFade?
}

/// A cross-fade of the light: the colour-shift token of the theme, as Core Animation timing.
nonisolated struct AmbientCAFade: Equatable, Sendable {
    nonisolated enum Curve: Equatable, Sendable { case easeIn, easeOut, easeInEaseOut }

    var duration: Double
    var curve: Curve

    var timingFunction: CAMediaTimingFunction {
        switch curve {
        case .easeIn: CAMediaTimingFunction(name: .easeIn)
        case .easeOut: CAMediaTimingFunction(name: .easeOut)
        case .easeInEaseOut: CAMediaTimingFunction(name: .easeInEaseOut)
        }
    }

    /// `kind` of the theme's motion table (DESIGN.md §4.1–§4.2): its reduced curve under Reduce Motion, none under
    /// Motion ▸ Instant. Springs and smooth curves become ease-in-out of the same duration.
    static func motion(_ kind: CrannyMotion.Kind, personality: MotionPersonality, reduceMotion: Bool) -> AmbientCAFade? {
        guard personality != .instant else { return nil }
        let curve = reduceMotion ? CrannyMotion.reducedSpec(kind) : CrannyMotion.spec(kind).curve
        switch curve {
        case .easeIn(let d)?: return AmbientCAFade(duration: d, curve: .easeIn)
        case .easeOut(let d)?: return AmbientCAFade(duration: d, curve: .easeOut)
        case .easeInOut(let d)?, .smooth(let d)?, .spring(let d, _)?: return AmbientCAFade(duration: d, curve: .easeInEaseOut)
        case nil: return nil
        }
    }
}

/// The light's clock (see the header): the time math of the clock layer, kept apart so it can be tested.
nonisolated enum AmbientCAClock {
    /// The local time of the clock layer at the light's time 0: every looping animation begins here. Not 0, because an
    /// animation whose `beginTime` is 0 begins whenever it is added.
    static let epoch: CFTimeInterval = 1

    /// The clock layer's timing for a light at `time` seconds: running from the parent's time `parentNow` on (speed 1)
    /// or standing still (speed 0).
    struct Timing: Equatable {
        var speed: Float
        var beginTime: CFTimeInterval
        var timeOffset: CFTimeInterval
    }

    static func timing(time: Double, running: Bool, parentNow: CFTimeInterval) -> Timing {
        running ? Timing(speed: 1, beginTime: parentNow - (epoch + time), timeOffset: 0)
                : Timing(speed: 0, beginTime: 0, timeOffset: epoch + time)
    }

    /// The light's time shown by a clock layer with `timing` at the parent's time `parentNow`.
    static func time(of timing: Timing, parentNow: CFTimeInterval) -> Double {
        (parentNow - timing.beginTime) * Double(timing.speed) + timing.timeOffset - epoch
    }

    /// Frames per second of the light's animations for the budget's `interval` (30 on AC, 20 on battery).
    static func frameRate(interval: Double?) -> Float {
        guard let interval, interval > 0 else { return 30 }
        return Float((1 / interval).rounded())
    }
}
