// CrannyEffects/EffectPath.swift — which renderer draws an effect (ARCHITECTURE.md D13, DESIGN.md §5.6 rule 1, §5.7).
// Pure decisions, unit-tested. Pausing (closed, occluded, full screen) never changes a path: only Appearance ▸ Quality,
// Reduce Motion, Low Power / thermal and the availability of the Metal library do, so nothing jumps when time stops.
// With Quality ▸ Efficient the Metal library is never asked about (asking loads it on a GPU device).
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
    /// Appearance ▸ Quality ▸ Efficient on a live view (`AmbientCALayer`): Core Animation layers that the window
    /// server animates, no Metal in the process. It also covers Reduce Motion (its layers stop on the resting frame).
    case coreAnimation

    /// - Parameters:
    ///   - detail: Appearance ▸ Quality; pass `.detailed` for a view that renders `.inline` (snapshots keep the SwiftUI
    ///     paths whatever the setting).
    ///   - shadersAvailable: `ShaderEffects.isAvailable`; not evaluated for `.efficient` or under Low Power.
    ///   - layerAllowed: the layer may be used here (`ShaderEffects.allowsLayer` and the view's `AmbientLightRendering`);
    ///     evaluated only when shaders run.
    static func resolve(budget: EffectBudget, detail: AmbientDetail = .detailed, shadersAvailable: @autoclosure () -> Bool,
                        layerAllowed: @autoclosure () -> Bool) -> AmbientPath {
        if budget.lowPower { return .staticHalo }
        if detail == .efficient { return .coreAnimation }
        if budget.reduceMotion || !shadersAvailable() { return .fallback }
        return layerAllowed() ? .layer : .shader
    }

    /// The light is drawn by a Metal shader on this path (stitchable or layer).
    var isShader: Bool { self == .shader || self == .layer }
}

/// How a one-shot delight moment (ember burst, charge sweep, first light, liquid neck) is drawn.
nonisolated enum MomentPath: Equatable, Sendable {
    /// Reduce Motion, and Appearance ▸ Quality ▸ Efficient: the moment's still variant (DESIGN.md §5.5, last column),
    /// which needs neither Metal nor a Canvas (both would give the process a GPU context, DESIGN.md §5.7).
    case reduced
    /// The stitchable shader.
    case shader
    /// The SwiftUI fallback: Canvas particles, `trim` sweep, Canvas blur neck, radial fade.
    case fallback

    /// - Parameter shadersAvailable: `ShaderEffects.isAvailable`; not evaluated for the still variant.
    static func resolve(budget: EffectBudget, detail: AmbientDetail = .detailed,
                        shadersAvailable: @autoclosure () -> Bool) -> MomentPath {
        if budget.reduceMotion || detail == .efficient { return .reduced }
        return shadersAvailable() && !budget.lowPower ? .shader : .fallback
    }
}

/// Where the ambient light (`AmbientLayer`, `AuroraField`, `MotesField`, `TideField`, `HaloField`) is drawn. Set it
/// with `View.ambientLightRendering(_:)`.
public nonisolated enum AmbientLightRendering: Equatable, Sendable {
    /// The default: a dedicated `CAMetalLayer` (a platform view) whenever shaders run, or with Appearance ▸ Quality ▸
    /// Efficient the Core Animation layers of `AmbientCALayer` (also a platform view), so SwiftUI does no work per
    /// frame. Like any platform view it is invisible to `ImageRenderer`, `NSView.cacheDisplay(in:to:)` and
    /// `drawingGroup()`, and `.layerEffect`, `.colorEffect` or `.distortionEffect` applied over it do not reach it.
    case automatic
    /// Every path stays inside SwiftUI (the stitchable shaders, timed by `EffectClock`): for snapshots, offscreen
    /// rendering and effects composited over the light, whatever Appearance ▸ Quality says. SwiftUI then redraws the
    /// light on every frame (at 30 fps about twice the CPU of the Metal layer, ARCHITECTURE.md §10.1 issue 1), so keep
    /// the default on screen.
    case inline
}
