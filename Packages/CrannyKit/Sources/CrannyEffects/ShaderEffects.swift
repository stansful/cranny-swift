// CrannyEffects/ShaderEffects.swift — the Metal library of CrannyEffects and the one switch between
// the shader path and the SwiftUI fallback (ARCHITECTURE D13, DESIGN.md §5.6).
import Foundation
import Metal
import SwiftUI
import os
import CrannyCore

private nonisolated let log = Log.logger(.effects)

enum ShaderEffects {
    /// `default.metallib`, compiled by SwiftPM from `Shaders/*.metal` into `CrannyKit_CrannyEffects.bundle`.
    nonisolated static let library = ShaderLibrary.bundle(.module)

    /// The SwiftUI stitchable functions (`.colorEffect`, `.layerEffect`, `.distortionEffect`).
    nonisolated static let stitchableFunctions: Set<String> = [
        "crannyDither", "auroraField", "tideField", "motesField", "haloGlow",
        "songRipple", "liquidNeck", "emberBurst", "chargeSweep",
    ]

    /// The render pipeline of the ambient Metal layer (`AmbientRenderer`): one vertex and one fragment per effect.
    nonisolated static let layerFunctions: Set<String> = [
        "ambientVertex", "auroraFragment", "tideFragment", "motesFragment", "haloFragment",
    ]

    /// Every function the effects call. A missing stitchable function renders TRANSPARENT without any error,
    /// so availability is checked once, up front, against this list.
    nonisolated static let requiredFunctions: Set<String> = stitchableFunctions.union(layerFunctions)

    /// QA switch: launching with `-CrannyDisableShaders YES` forces every SwiftUI fallback.
    nonisolated static let disableKey = "CrannyDisableShaders"

    /// QA switch: launching with `-CrannyDisableEffectLayer YES` draws the ambient light with the SwiftUI
    /// stitchable shaders instead of the dedicated Metal layer (energy A/B runs). Release builds honour it too.
    nonisolated static let disableLayerKey = "CrannyDisableEffectLayer"

    /// true when the metallib is bundled, loads on this Mac's GPU and contains every required function.
    nonisolated static let isAvailable: Bool = {
        guard let problem = unavailabilityReason() else { return true }
        log.info("Metal effects off (\(problem, privacy: .public)); using the SwiftUI fallbacks")
        return false
    }()

    /// Why the Metal effects cannot run here, or nil. `defaults` holds the launch arguments (tests pass their own).
    nonisolated static func unavailabilityReason(defaults: UserDefaults = .standard) -> String? {
        if defaults.bool(forKey: disableKey) { return "\(disableKey) is set" }
        guard let url = libraryURL else { return "default.metallib is not in the bundle" }
        guard let device = MTLCreateSystemDefaultDevice() else { return "no Metal device" }
        guard let metalLibrary = try? device.makeLibrary(URL: url) else { return "default.metallib does not load" }
        let missing = requiredFunctions.subtracting(metalLibrary.functionNames)
        return missing.isEmpty ? nil : "missing " + missing.sorted().joined(separator: ", ")
    }

    /// The compiled library inside the module bundle (the ambient layer loads it with `makeLibrary(URL:)`).
    nonisolated static var libraryURL: URL? { Bundle.module.url(forResource: "default", withExtension: "metallib") }

    /// Whether the ambient light may use the dedicated Metal layer (`-CrannyDisableEffectLayer` is not set).
    nonisolated static var allowsLayer: Bool { allowsLayer(defaults: .standard) }

    nonisolated static func allowsLayer(defaults: UserDefaults) -> Bool { !defaults.bool(forKey: disableLayerKey) }

    /// The shader path runs only while animation is allowed: Reduce Motion, Low Power / thermal ≥ serious
    /// and an unavailable library always use the SwiftUI fallback.
    static func usesShader(_ budget: EffectBudget) -> Bool {
        isAvailable && !budget.reduceMotion && !budget.lowPower
    }
}

extension View {
    /// Last pass of every gradient-producing effect (aurora, tide, halo): ±0.5 LSB of noise against banding.
    func crannyDithered(scale: CGFloat, isEnabled: Bool = true) -> some View {
        colorEffect(ShaderEffects.library.crannyDither(.float(1), .float(scale)), isEnabled: isEnabled)
    }
}
