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

    /// Under Reduce Motion open, close and resize do not travel: the old and new shapes cross-fade at their
    /// final sizes (`CrannyMotion.morphsShape`). Every presentation with the same key morphs; a new key
    /// cross-fades. Without Reduce Motion the key never changes.
    static func crossFadeKey(phase: NotchPhase, openColumns: Int, isFocusMode: Bool, reduceMotion: Bool) -> String {
        guard reduceMotion else { return "morph" }
        guard phase == .open else { return "band" }                       // closed, breath, compact, peek: small morphs
        return isFocusMode ? "open.focus" : "open.\(openColumns)"
    }

    /// The animation of a shape change, with the close delay applied.
    static func animation(_ kind: CrannyMotion.Kind, theme: CrannyTheme) -> Animation? {
        let delay = delay(for: kind, reduceMotion: theme.reduceMotion)
        return theme.animation(kind).map { delay > 0 ? $0.delay(delay) : $0 }
    }
}

/// Timings of content around a shape change (DESIGN.md §4.3).
nonisolated enum ContentTiming {
    /// Compact slot content grows out of the camera edge 0.08 s after the shape starts (`activityIn`).
    static let slotDelay: Double = 0.08
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
