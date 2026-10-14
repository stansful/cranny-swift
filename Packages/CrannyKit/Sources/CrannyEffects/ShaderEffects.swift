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
    static let library = ShaderLibrary.bundle(.module)

    /// Every stitchable function the effects call. A missing function renders TRANSPARENT without any
    /// error, so availability is checked once, up front. WP11 adds each function it ships.
    nonisolated static let requiredFunctions: Set<String> = ["crannyDither", "auroraField"]

    /// QA switch: launching with `-CrannyDisableShaders YES` forces every SwiftUI fallback.
    nonisolated static let disableKey = "CrannyDisableShaders"

    /// true when the metallib is bundled, loads on this Mac's GPU and contains every required function.
    nonisolated static let isAvailable: Bool = {
        guard let problem = unavailabilityReason() else { return true }
        log.info("Metal effects off (\(problem, privacy: .public)); using the SwiftUI fallbacks")
        return false
    }()

    nonisolated static func unavailabilityReason() -> String? {
        if UserDefaults.standard.bool(forKey: disableKey) { return "\(disableKey) is set" }
        guard let url = Bundle.module.url(forResource: "default", withExtension: "metallib") else {
            return "default.metallib is not in the bundle"
        }
        guard let device = MTLCreateSystemDefaultDevice() else { return "no Metal device" }
        guard let metalLibrary = try? device.makeLibrary(URL: url) else { return "default.metallib does not load" }
        let missing = requiredFunctions.subtracting(metalLibrary.functionNames)
        return missing.isEmpty ? nil : "missing " + missing.sorted().joined(separator: ", ")
    }

    /// The shader path runs only while animation is allowed: Reduce Motion, Low Power / thermal ≥ serious
    /// and an unavailable library always use the SwiftUI fallback.
    static func usesShader(_ budget: EffectBudget) -> Bool {
        isAvailable && !budget.reduceMotion && !budget.lowPower
    }
}

extension View {
    /// Last pass of every gradient-producing effect (aurora, tide, halo): ±0.5 LSB of noise against banding.
    func crannyDithered(scale: CGFloat) -> some View {
        colorEffect(ShaderEffects.library.crannyDither(.float(1), .float(scale)))
    }
}
