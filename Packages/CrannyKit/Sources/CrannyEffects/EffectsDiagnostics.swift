// CrannyEffects/EffectsDiagnostics.swift — the one public window onto the internal `ShaderEffects`
// (ARCHITECTURE.md D13), for `Cranny --diagnostics` and scripts/smoke.sh.
import Foundation

public nonisolated enum EffectsDiagnostics {
    /// "ok" when the Metal effects can run here; otherwise why every effect uses its SwiftUI fallback
    /// ("default.metallib is not in the bundle", "no Metal device", "CrannyDisableShaders is set", "missing …").
    public static var shaderStatus: String { ShaderEffects.unavailabilityReason() ?? "ok" }
}
