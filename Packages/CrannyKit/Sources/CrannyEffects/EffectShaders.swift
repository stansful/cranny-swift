// CrannyEffects/EffectShaders.swift — the Metal shader library of CrannyEffects.
// `Shaders/*.metal` are compiled by SwiftPM (and by Xcode inside the app) into `default.metallib` in this
// module's resource bundle (`CrannyKit_CrannyEffects.bundle`), loaded with `ShaderLibrary.bundle(.module)`.
// Every shader has a SwiftUI fallback: callers check `isAvailable` and honour Reduce Motion / Low Power.
import CrannyCore
import Foundation
import Metal
import os
import SwiftUI

nonisolated private let log = Log.logger(.effects)

public nonisolated enum EffectShaders {
    /// `[[ stitchable ]]` function names; each must exist in `Shaders/*.metal`.
    static let auroraFunction = "crannyAurora"
    static let allFunctions = [auroraFunction]

    /// This module's resource bundle (tests and diagnostics).
    static var bundle: Bundle { .module }

    /// The compiled shader library, or nil if the bundle has none (built without the Metal Toolchain).
    public static var libraryURL: URL? { Bundle.module.url(forResource: "default", withExtension: "metallib") }

    /// The library exists, this Mac has a Metal device and the library contains every function.
    /// Evaluated once, on first use (the first time an effect is about to draw).
    public static let isAvailable: Bool = {
        guard libraryURL != nil else {
            log.info("no default.metallib in the CrannyEffects bundle; using the SwiftUI effects")
            return false
        }
        guard let device = MTLCreateSystemDefaultDevice() else {
            log.info("no Metal device; using the SwiftUI effects")
            return false
        }
        do {
            let library = try device.makeDefaultLibrary(bundle: .module)
            let missing = allFunctions.filter { library.makeFunction(name: $0) == nil }
            if !missing.isEmpty {
                log.error("shader library lacks \(missing.joined(separator: ", "), privacy: .public); using the SwiftUI effects")
            }
            return missing.isEmpty
        } catch {
            log.error("shader library failed to load: \(error.localizedDescription, privacy: .public); using the SwiftUI effects")
            return false
        }
    }()

    /// One line for `Cranny --diagnostics`.
    public static var status: String {
        guard let url = libraryURL else { return "(missing)" }
        return isAvailable ? "ok \(url.lastPathComponent)" : "unavailable \(url.lastPathComponent)"
    }

    /// The aurora colour effect (see `Shaders/Aurora.metal`). `size` is the drawn area in points;
    /// `cap` = `Glow.ambientAlphaCap(level)`; time in seconds (wrapped by the caller).
    static func aurora(size: CGSize, time: Double, energy: Double, cap: Double, palette: AmbientPalette) -> Shader {
        Shader(function: ShaderFunction(library: .bundle(.module), name: auroraFunction), arguments: [
            .float2(size), .float(time), .float(energy), .float(cap),
            .color(palette.glow1.color), .color(palette.glow2.color), .color(palette.glow3.color),
        ])
    }
}
