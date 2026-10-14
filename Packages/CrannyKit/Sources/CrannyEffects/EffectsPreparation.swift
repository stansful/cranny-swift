// CrannyEffects/EffectsPreparation.swift — one-time GPU preparation before the effects are first seen (DESIGN.md §5.6).
//
// Without it the first open loads the Metal library and compiles the ambient layer's four pipelines on the main thread,
// during the open animation, and each moment's SwiftUI shader compiles the first time it plays (a hitch at the first
// timer done, charger sweep, satellite split or First light). `prepare()` does both once per launch at utility
// priority, off the main thread. Nothing is drawn, no timer runs, and only what the light keeps anyway is kept
// (`AmbientRenderer.prewarm()`).
import CrannyCore
import SwiftUI

/// Prepares the Metal effects ahead of their first use, so they start without a compile on the main thread.
public enum EffectsPreparation {
    private static var isPrepared = false

    /// Builds the ambient light's renderer and compiles the moments' shaders (macOS 15 and later) off the main thread.
    /// Call it once per launch while the app is idle (for example a few seconds after launch); later calls return at
    /// once. Pixels and fallbacks are unchanged: an effect that finds nothing prepared builds it itself, as before.
    public static func prepare() async {
        guard !isPrepared else { return }
        isPrepared = true
        await AmbientRenderer.prewarm()
        if #available(macOS 15.0, *) { await precompileMomentShaders() }
    }

    /// The stitchable functions of the moments, compiled for the way the moments use them (the arguments only give
    /// their types). The ambient fields and `songRipple` run as stitchable functions only on the `.inline` and SwiftUI
    /// shader paths, so they are left to compile on first use.
    @available(macOS 15.0, *)
    static func precompileMomentShaders() async {
        guard ShaderEffects.isAvailable else { return }
        let library = ShaderEffects.library
        let color = Shader.Argument.color(.black)
        let shaders: [(Shader, Shader.UsageType)] = [
            (library.emberBurst(.boundingRect, .float2(0, 0), .float(0), .colorArray([.black]), .float(0)), .colorEffect),
            (library.chargeSweep(.float4(0, 0, 1, 1), .float(0), color, .float(0)), .colorEffect),
            (library.haloGlow(.boundingRect, .float2(0.5, 0), .float(1), color, .float(0)), .colorEffect),
            (library.crannyDither(.float(1), .float(2)), .colorEffect),
            (library.liquidNeck(.float(0), .float(0), color), .layerEffect),
        ]
        for (shader, usage) in shaders {
            try? await shader.compile(as: usage)              // a failure only means it compiles on first use, as before
        }
    }
}
