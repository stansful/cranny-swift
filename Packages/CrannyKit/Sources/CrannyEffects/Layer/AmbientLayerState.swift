// CrannyEffects/Layer/AmbientLayerState.swift — what the ambient Metal layer draws, and the uniforms its fragment
// functions read (`cranny::AmbientUniforms` in Shaders/CrannyShaders.h; the layouts must match).
import CrannyCore
import Foundation
import SwiftUI
import simd

/// Where the `.halo` effect blooms: a unit point in the layer and a radius in points.
nonisolated struct HaloPlacement: Equatable, Sendable {
    var center: UnitPoint
    var radius: CGFloat
    /// The ambient halo: centred on the bottom edge, r 260 (DESIGN.md §5.6).
    static let ambient = HaloPlacement(center: .bottom, radius: 260)
}

/// Everything the layer needs besides time and size. SwiftUI hands a new value to the view on every update; the
/// layer redraws only when it is paused (otherwise its own clock picks the change up on the next frame).
nonisolated struct AmbientLayerState: Equatable, Sendable {
    var effect: AmbientEffect
    var glows: [RGB]
    var energy: Double
    var level: AmbienceLevel
    var fill: Double
    var reveal: AmbientReveal?
    var rippleStart: Date?
    var halo: HaloPlacement
    /// `EffectBudget.minimumInterval`: the frame interval, or nil while paused.
    var interval: Double?
    var restingTime: Double
}

/// Mirror of `cranny::AmbientUniforms`: eleven 16-byte vectors, 176 bytes on arm64 and x86_64.
nonisolated struct AmbientUniforms {
    var frame: SIMD4<Float>     // width, height (pt), scale (px per pt), time (s)
    var params: SIMD4<Float>    // energy, intensity, cap, fill
    var reveal: SIMD4<Float>    // centre x, y (pt), radius, feather; radius < 0 = off
    var ripple: SIMD4<Float>    // centre x, y (pt), seconds since the trigger, 1 = playing
    var halo: SIMD4<Float>      // centre x, y (unit), radius (pt), dither amount
    var stops: (SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>)
    var counts: SIMD4<Int32>    // stop count, pixel rows of the layer above the drawable (`AmbientDrawableLayout.offset`)

    static let maxStops = 5

    /// Uniforms for one frame of `state` at `time` (shader seconds) on a layer of `size` points, drawn into a drawable
    /// that starts `rowOffset` pixel rows below the layer's top (0: a drawable of the whole layer).
    init(state: AmbientLayerState, size: CGSize, scale: CGFloat, time: Double, date: Date, rowOffset: Int = 0) {
        let rippleElapsed = Ripple.elapsed(since: state.rippleStart, at: date)
        frame = SIMD4(Float(size.width), Float(size.height), Float(scale), Float(time))
        params = SIMD4(Float(Ripple.energy(state.energy, elapsed: rippleElapsed)), Float(state.level.intensity),
                       Float(Glow.ambientAlphaCap(state.level)), Float(min(max(state.fill, 0), 1)))
        if let reveal = state.reveal {
            self.reveal = SIMD4(Float(reveal.center.x * size.width), Float(reveal.center.y * size.height),
                                Float(reveal.radius), Float(reveal.feather))
        } else {
            self.reveal = SIMD4(0, 0, -1, 0)
        }
        ripple = rippleElapsed.map { SIMD4(Float(size.width / 2), 0, Float($0), 1) } ?? .zero
        let dither: Float = state.effect == .motes ? 0 : 1                // specks need no dither (as on SwiftUI)
        halo = SIMD4(Float(state.halo.center.x), Float(state.halo.center.y), Float(state.halo.radius), dither)
        let glows = Array(state.glows.prefix(Self.maxStops))
        func stop(_ i: Int) -> SIMD4<Float> {                    // clamped like `RGB.color`
            guard i < glows.count else { return .zero }
            let c = SIMD3(Float(glows[i].r), Float(glows[i].g), Float(glows[i].b))
            return SIMD4(simd_clamp(c, .zero, .one), 1)
        }
        stops = (stop(0), stop(1), stop(2), stop(3), stop(4))
        counts = SIMD4(Int32(glows.count), Int32(clamping: rowOffset), 0, 0)
    }
}
