// CrannyTodos/Model/TodoDelight.swift — the "To-do done" moment (DESIGN.md §5.5): the check draws itself
// (trim 0 → 1, 0.25 s) and Lively adds six motes. It is drawn inside the widget, not by CrannyEffects
// (ARCHITECTURE.md §10.7). Pure decisions and mote geometry, unit-tested.
import CrannyCore
import CoreGraphics
import Foundation
import SwiftUI

/// How a check appears when a to-do is completed.
nonisolated enum TodoCheckStyle: Equatable, Sendable {
    /// Calm, Instant, Reduce Motion, full screen, Live Activities paused: the check is simply there.
    case instant
    /// Standard: the check draws itself.
    case draw
    /// Lively: the check draws itself and six motes rise from the circle.
    case drawWithMotes

    /// Delight caps (DESIGN.md §5.5): none in full screen or while Live Activities are paused; Calm and
    /// Reduce Motion get the instant check; Instant animates nothing. Appearance ▸ Quality ▸ Efficient keeps Lively's
    /// check without the motes: they are a Canvas, which would give Cranny the GPU memory that setting saves (§5.7).
    static func resolve(personality: MotionPersonality, reduceMotion: Bool, detail: AmbientDetail = .detailed,
                        isFullScreenInFront: Bool, areActivitiesPaused: Bool) -> TodoCheckStyle {
        if reduceMotion || isFullScreenInFront || areActivitiesPaused { return .instant }
        switch personality {
        case .calm, .instant: return .instant
        case .standard: return .draw
        case .lively: return detail == .efficient ? .draw : .drawWithMotes
        }
    }

    /// The check's trim and fill (DESIGN.md §5.5: 0.25 s). nil = no animation.
    var animation: Animation? { self == .instant ? nil : .easeOut(duration: TodoDelightTiming.checkDraw) }
}

/// Durations of the moment. DESIGN.md §5.5 gives the check (0.25 s); the motes' 0.6 s matches the rise of
/// the check plus a short drift, and stays under the timer ember burst (0.9 s).
nonisolated enum TodoDelightTiming {
    static let checkDraw: Double = 0.25
    static let motes: Double = 0.6
    /// A checked to-do stays visible, struck through, this long before it collapses (DESIGN.md §7.6).
    static let linger: Duration = .milliseconds(1200)
}

/// One of the six stateless motes: everything is a function of `progress` (0…1) and a seed.
nonisolated struct TodoMote: Equatable, Sendable {
    static let count = 6

    /// Direction in radians (0 = right, counter-clockwise in a y-down canvas means up is −π/2).
    let angle: Double
    /// Travel from the circle's edge, in points.
    let travel: CGFloat
    /// Radius at the start; it shrinks to 40 % while fading.
    let radius: CGFloat

    init(index: Int, seed: UInt64) {
        var rng = SplitMix64(seed: seed &+ UInt64(index) &* 0x9E37_79B9_7F4A_7C15)
        // Evenly around the circle, tilted upward a little (light rises), with ±12° jitter.
        let base = Double(index) / Double(Self.count) * 2 * .pi - .pi / 2
        angle = base + (rng.unit() - 0.5) * (24 * .pi / 180)
        travel = 6 + CGFloat(rng.unit()) * 6
        radius = 1.2 + CGFloat(rng.unit()) * 0.8
    }

    /// Centre at `progress`, measured from the checkbox centre, starting at `startRadius` (its edge).
    func offset(at progress: Double, startRadius: CGFloat) -> CGSize {
        let eased = 1 - pow(1 - min(max(progress, 0), 1), 3)            // ease-out cubic
        let distance = startRadius + travel * CGFloat(eased)
        return CGSize(width: cos(angle) * distance, height: sin(angle) * distance - CGFloat(eased) * 2)
    }

    /// Fades in over the first 15 %, then out; 0 at both ends.
    func opacity(at progress: Double) -> Double {
        let p = min(max(progress, 0), 1)
        return p < 0.15 ? p / 0.15 : max(0, 1 - (p - 0.15) / 0.85)
    }

    func radius(at progress: Double) -> CGFloat {
        radius * (1 - 0.6 * CGFloat(min(max(progress, 0), 1)))
    }

    /// A stable seed for a to-do (the same motes every time it is checked).
    static func seed(for id: UUID) -> UInt64 {
        withUnsafeBytes(of: id.uuid) { $0.loadUnaligned(as: UInt64.self) }
    }
}

/// Tiny deterministic generator for the mote layout (SplitMix64).
nonisolated struct SplitMix64 {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    /// Uniform in 0..<1.
    mutating func unit() -> Double { Double(next() >> 11) / Double(1 << 53) }
}
