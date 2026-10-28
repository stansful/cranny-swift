// CrannyEffects/EffectsDiagnostics.swift — the one public window onto the internal `ShaderEffects`
// (ARCHITECTURE.md D13), for `Cranny --diagnostics` and scripts/lib/smoke.sh.
import Foundation

/// Read-only status of the Metal effects for `Cranny --diagnostics` and `scripts/lib/smoke.sh`.
public nonisolated enum EffectsDiagnostics {
    /// "ok" when the Metal effects can run here; otherwise why every effect uses its SwiftUI fallback
    /// ("default.metallib is not in the bundle", "no Metal device", "CrannyDisableShaders is set", "missing …").
    public static var shaderStatus: String { ShaderEffects.unavailabilityReason() ?? "ok" }

    /// How the ambient light is drawn while motion is allowed: "metal-layer" (the dedicated `CAMetalLayer`),
    /// "swiftui-shader" (`-CrannyDisableEffectLayer YES`) or "fallback" (no shaders). Reduce Motion and Low Power
    /// always use the SwiftUI fallback.
    public static var ambientRenderer: String {
        guard ShaderEffects.unavailabilityReason() == nil else { return "fallback" }
        return ShaderEffects.allowsLayer ? "metal-layer" : "swiftui-shader"
    }
}
