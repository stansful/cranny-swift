// CrannyEffects/Layer/AmbientFrameTables.swift — values that are the same for every pixel of a frame, computed once per
// frame on the CPU and handed to the layer's fragment functions as `buffer(1)` (Shaders/Aurora.metal, Motes.metal).
//
// Why: per pixel they cost more than the light itself. The aurora converted its palette stops to OKLab four times per
// pixel (24 `pow`); a motes pixel rebuilt 9 motes from their hashes (54 hashes, 18 `sin`, 9 `fmod`). Here it is about a
// microsecond per frame, from the same uniforms and the same formulas (`oklab` below mirrors `cranny::oklab`,
// `MoteMath` is the Swift twin of `cranny::mote`), so the layer still draws what the stitchable functions draw.
import CoreGraphics
import Foundation
import simd

nonisolated enum AmbientFrameTables {
    /// The aurora's colours: the OKLab values of stops 0, 1 and 2 (indices modulo the stop count, black without stops),
    /// as `float4` (w unused). The stops are rounded to half precision first, as the shader's `half3` palette holds them.
    static func auroraLab(_ uniforms: AmbientUniforms, into table: inout [SIMD4<Float>]) {
        table.removeAll(keepingCapacity: true)
        for i in 0..<3 {
            let c = stop(uniforms, i)
            table.append(SIMD4(oklab(SIMD3(halfRounded(c.x), halfRounded(c.y), halfRounded(c.z))), 0))
        }
    }

    /// The 36 motes of this frame, two `float4` each: entry 2k is mote k's (centre x, y, radius, twinkle) in points,
    /// entry 2k + 1 its stop colour (rgb, the shader rounds it to `half3` like its palette), k = column · 3 + row.
    static func motes(_ uniforms: AmbientUniforms, into table: inout [SIMD4<Float>]) {
        table.removeAll(keepingCapacity: true)
        let size = CGSize(width: Double(max(uniforms.frame.x, 1)), height: Double(max(uniforms.frame.y, 1)))
        let time = Double(uniforms.frame.w), energy = Double(uniforms.params.x)
        for column in 0..<MoteMath.columns {
            for row in 0..<MoteMath.perColumn {
                let mote = MoteMath.mote(column: column, row: row, size: size, time: time, energy: energy)
                table.append(SIMD4(Float(mote.center.x), Float(mote.center.y), Float(mote.radius), Float(mote.twinkle)))
                table.append(SIMD4(stop(uniforms, mote.stop), 0))
            }
        }
    }

    /// Stop `i` modulo the stop count (`cranny::stop`), black without stops.
    static func stop(_ uniforms: AmbientUniforms, _ i: Int) -> SIMD3<Float> {
        let count = min(max(Int(uniforms.counts.x), 0), AmbientUniforms.maxStops)
        guard count > 0 else { return .zero }
        let s = uniforms.stops
        let value: SIMD4<Float>
        switch i % count {
        case 0: value = s.0
        case 1: value = s.1
        case 2: value = s.2
        case 3: value = s.3
        default: value = s.4
        }
        return SIMD3(value.x, value.y, value.z)
    }

    /// sRGB-encoded colour → OKLab (Ottosson 2020), the constants of `cranny::oklab`, in double precision.
    static func oklab(_ srgb: SIMD3<Float>) -> SIMD3<Float> {
        func linear(_ c: Float) -> Double {
            let c = Double(c)
            return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        func cubeRoot(_ x: Double) -> Double { x < 0 ? -pow(-x, 1.0 / 3.0) : pow(x, 1.0 / 3.0) }   // sign(x) · |x|^⅓
        let r = linear(srgb.x), g = linear(srgb.y), b = linear(srgb.z)
        let l = cubeRoot(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
        let m = cubeRoot(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
        let s = cubeRoot(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
        return SIMD3(Float(0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s),
                     Float(1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s),
                     Float(0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s))
    }

    /// `x` rounded to the nearest half-precision value, ties to even: what the shaders' `half3(float3)` conversion
    /// gives for palette stops (0…1). Written out because `Float16` is unavailable on Intel Macs.
    static func halfRounded(_ x: Float) -> Float {
        guard x.isFinite, x != 0 else { return x }
        let exponent = max(Int(x.exponent), -14)                 // half precision is subnormal below 2⁻¹⁴
        let quantum = Float(sign: .plus, exponent: exponent - 10, significand: 1)
        return (x / quantum).rounded(.toNearestOrEven) * quantum
    }
}
