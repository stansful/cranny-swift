// CrannyEffects/EffectPath.swift — which renderer draws an effect (ARCHITECTURE.md D13, DESIGN.md §5.6 rule 1).
// Pure decisions, unit-tested. Pausing (closed, occluded, full screen) never changes a path: only Reduce Motion,
// Low Power / thermal and the availability of the Metal library do, so nothing jumps when time stops.
import CrannyCore

/// How an ambient effect (aurora, motes, tide, halo) is drawn.
nonisolated enum AmbientPath: Equatable, Sendable {
    /// Low Power / thermal ≥ serious: the static SwiftUI halo (`RadialGradient`), whatever the effect.
    case staticHalo
    /// The SwiftUI fallback (MeshGradient / Canvas). Reduce Motion freezes it on its resting frame.
    case fallback
    /// The SwiftUI stitchable shader, timed by `EffectClock` (invalidates SwiftUI on every frame).
    case shader
    /// The dedicated Metal layer (`AmbientMetalView`): same shader math, its own frame pacing, no SwiftUI
    /// invalidation per frame. The default whenever shaders run.
    case layer

    /// - Parameters:
    ///   - shadersAvailable: `ShaderEffects.isAvailable`.
    ///   - layerAllowed: the layer may be used here (`ShaderEffects.allowsLayer` and the view's `EffectRendering`).
    static func resolve(budget: EffectBudget, shadersAvailable: Bool, layerAllowed: Bool) -> AmbientPath {
        if budget.lowPower { return .staticHalo }
        if budget.reduceMotion || !shadersAvailable { return .fallback }
        return layerAllowed ? .layer : .shader
    }

    /// The light is drawn by a Metal shader on this path (stitchable or layer).
    var isShader: Bool { self == .shader || self == .layer }
}

/// How a one-shot delight moment (ember burst, charge sweep, first light, liquid neck) is drawn.
nonisolated enum MomentPath: Equatable, Sendable {
    /// Reduce Motion: the moment's static variant (DESIGN.md §5.5, last column).
    case reduced
    /// The stitchable shader.
    case shader
    /// The SwiftUI fallback: Canvas particles, `trim` sweep, Canvas blur neck, radial fade.
    case fallback

    static func resolve(budget: EffectBudget, shadersAvailable: Bool) -> MomentPath {
        if budget.reduceMotion { return .reduced }
        return shadersAvailable && !budget.lowPower ? .shader : .fallback
    }
}

/// Where a view may draw its ambient light. `.inline` keeps every path inside SwiftUI (no `NSView`), for
/// `ImageRenderer` snapshots and tests; `.automatic` uses the Metal layer whenever shaders run.
nonisolated enum EffectRendering: Equatable, Sendable {
    case automatic
    case inline
}
