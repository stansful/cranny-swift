// CrannyNotchUI/Choreography/ContentTransitions.swift — which spring moves the shape and how content enters
// and leaves for every change of presentation (DESIGN.md §4.1–§4.3). Pure functions: unit-tested.
import CrannyCore
import SwiftUI

/// The part of a scene that decides the shape's motion.
nonisolated struct ShapeMotionState: Equatable, Sendable {
    var phase: NotchPhase
    /// The primary activity is a HUD (P0): it enters with `hudIn` and leaves with `hudOut`.
    var isHUD = false
}

nonisolated enum ShapeMotion {
    /// The spring for a change from `old` to `new`. Rule (DESIGN.md §4.1): geometry may overshoot when it grows,
    /// and never when it shrinks back into the hardware — every "out" kind lands with bounce 0.
    static func kind(from old: ShapeMotionState, to new: ShapeMotionState) -> CrannyMotion.Kind {
        switch (old.phase, new.phase) {
        case (.open, .open): return .resize                               // tab / page height, Notes focus
        case (_, .open): return .open
        case (.open, _): return .close
        case (.peek, .peek): return .peekIn                               // rows added or removed
        case (_, .peek): return .peekIn
        case (.peek, .compact): return .peekOut
        case (.peek, _): return .close
        case (.compact, .compact):
            if new.isHUD && !old.isHUD { return .hudIn }
            if old.isHUD && !new.isHUD { return .hudOut }
            return .activitySwap
        case (_, .compact): return new.isHUD ? .hudIn : .activityIn
        case (.compact, _): return old.isHUD ? .hudOut : .activityOut
        case (.idle, .breath), (.hidden, .breath): return .hoverIn
        case (.breath, _): return .hoverOut
        default: return .close                                            // idle ⇄ hidden, layout changes: land
        }
    }

    /// The camera "swallows an empty shape": a close starts 0.04 s after the content left (DESIGN.md §4.3).
    static func delay(for kind: CrannyMotion.Kind, reduceMotion: Bool) -> Double {
        kind == .close && !reduceMotion ? 0.04 : 0
    }

    /// Under Reduce Motion open and close do not travel: the old and new surfaces cross-fade at their final
    /// sizes (`CrannyMotion.morphsShape`), so opening and closing change the key. Every presentation with the
    /// same key keeps the same surface. An open → open resize keeps the key too (the open panel inside must stay
    /// the same view for focus and VoiceOver); `ResizeCrossFade` cross-fades its outlines instead. Without Reduce
    /// Motion the key never changes.
    static func crossFadeKey(phase: NotchPhase, reduceMotion: Bool) -> String {
        guard reduceMotion else { return "morph" }
        return phase == .open ? "open" : "band"                           // closed, breath, compact, peek: small morphs
    }

    /// The animation of a shape change, with the close delay applied. Under Reduce Motion a resize has none: the
    /// shape takes its new size at once and `ResizeCrossFade` dissolves the outlines.
    static func animation(_ kind: CrannyMotion.Kind, theme: CrannyTheme) -> Animation? {
        if !CrannyMotion.morphsShape(kind, reduceMotion: theme.reduceMotion) && kind == .resize { return nil }
        let delay = delay(for: kind, reduceMotion: theme.reduceMotion)
        return theme.animation(kind).map { delay > 0 ? $0.delay(delay) : $0 }
    }

    // MARK: A swipe-down open carries the gesture's velocity (DESIGN.md §4.4)

    /// The open spring of a swipe-down open: the `open` token (its duration, its bounce scaled by the personality,
    /// so Calm still lands without overshoot) started at the fingers' speed, as a share of the distance the bottom
    /// edge travels per second. Reduce Motion (a dissolve at the final size) and Instant ignore the velocity, and so
    /// does an open with no travel to carry it over.
    static func openAnimation(velocity: CGFloat, from: NotchGeometry, to: NotchGeometry, theme: CrannyTheme) -> Animation? {
        guard !theme.reduceMotion, theme.motion != .instant,
              let initial = relativeVelocity(velocity, travel: to.bottom - from.bottom),
              case .spring(let duration, let bounce) = CrannyMotion.spec(.open).curve else {
            return animation(.open, theme: theme)
        }
        return .interpolatingSpring(duration: duration, bounce: min(bounce * theme.motion.bounceScale, 0.35),
                                    initialVelocity: initial)
    }

    /// The fingers' speed (pt/s) as the spring's initial velocity (shares of the change per second), at most
    /// `maximumCarry`; nil when there is nothing to carry (no speed, or under a point of travel).
    static func relativeVelocity(_ velocity: CGFloat, travel: CGFloat) -> Double? {
        guard velocity > 0, travel >= 1 else { return nil }
        return min(Double(velocity / travel), maximumCarry)
    }

    /// A flick never throws the shape: at 8 shares per second the `open` spring overshoots about 0.7 % (Lively
    /// 2.2 %, Calm none) instead of 0.5 % from rest, and a fast flick still settles in the token's time.
    static let maximumCarry: Double = 8
}

/// Timings of content around a shape change (DESIGN.md §4.3).
nonisolated enum ContentTiming {
    /// Compact slot content grows out of the camera edge 0.08 s after the shape starts (`activityIn`).
    static let slotDelay: Double = 0.08
    /// … and returns about 0.22 s into a close, when the shape is nearly back (DESIGN.md §4.3 "Close").
    static let slotReturnDelay: Double = 0.22

    /// The wing delay for a change of presentation.
    static func slotDelay(after kind: CrannyMotion.Kind) -> Double {
        kind == .close || kind == .peekOut ? slotReturnDelay : slotDelay
    }
    /// Content waits until the shape is about 25 % open (`contentIn` already carries its 0.06 s delay).
    static let headerDelay: Double = 0.06
    /// Peek rows stagger 30 ms top to bottom (DESIGN.md §4.5).
    static let peekRowStep: Double = 0.030

    /// Extra delay of a peek row after `contentIn`'s own delay. Reduce Motion: none.
    static func peekRowDelay(index: Int, reduceMotion: Bool) -> Double {
        reduceMotion ? 0 : Double(min(max(index, 0), 3)) * peekRowStep
    }
}

extension CrannyTheme {
    /// `contentIn` with an extra delay (stagger, slot growth), or nil under Instant.
    func contentIn(after delay: Double) -> Animation? {
        animation(.contentIn).map { delay > 0 ? $0.delay(delay) : $0 }
    }
}

extension AnyTransition {
    /// Content that only leaves with an animation (`contentOut`); its own children animate the entrance
    /// (staggered widgets, the header), so the insertion is immediate.
    static func crannyLeaving(_ theme: CrannyTheme) -> AnyTransition {
        .asymmetric(insertion: .identity, removal: .opacity.animation(theme.animation(.contentOut)))
    }
}
