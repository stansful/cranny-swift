// CrannyEffects/Shaders/CrannyShaders.h — helpers shared by the CrannyEffects shaders (DESIGN.md §5.6).
// `#include "CrannyShaders.h"` resolves next to the .metal files; SwiftPM does not copy the header.
#pragma once
#include <metal_stdlib>
using namespace metal;

namespace cranny {

/// Interleaved gradient noise (Jimenez 2014) in 0..<1: a cheap, texture-free stand-in for blue noise.
static inline float ign(float2 pixel) {
    return fract(52.9829189 * fract(dot(pixel, float2(0.06711056, 0.00583715))));
}

/// Stateless integer hash in 0...1 (seeds noise lattices and particles; nothing keeps per-particle state).
static inline float hash(uint n) {
    n = (n << 13U) ^ n;
    n = n * (n * n * 15731U + 789221U) + 1376312589U;
    return float(n & 0x7fffffffU) / float(0x7fffffffU);
}
static inline float hash21(float2 lattice) {
    int2 i = int2(floor(lattice));
    return hash(uint(i.x) * 1597334677U ^ uint(i.y) * 3812015801U);
}

/// Smooth value noise in 0...1.
static inline float valueNoise(float2 p) {
    float2 i = floor(p), f = fract(p);
    float2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash21(i), hash21(i + float2(1, 0)), u.x),
               mix(hash21(i + float2(0, 1)), hash21(i + float2(1, 1)), u.x), u.y);
}

/// Fractal Brownian motion: `octaves` of value noise (lacunarity 2, gain 0.5), normalised to 0...1.
static inline float fbm(float2 p, int octaves) {
    float sum = 0.0, amplitude = 0.5, norm = 0.0;
    for (int i = 0; i < octaves; i++) {
        sum += amplitude * valueNoise(p);
        norm += amplitude;
        p = p * 2.0 + float2(17.0, 9.0);
        amplitude *= 0.5;
    }
    return sum / max(norm, 1e-4);
}

/// Piecewise-linear ramp through the palette stops (`.colorArray`, 1–5 entries), t in 0...1.
static inline half3 ramp(device const half4 *stops, int count, float t) {
    if (count <= 1) { return count == 1 ? stops[0].rgb : half3(0.0h); }
    float x = clamp(t, 0.0, 1.0) * float(count - 1);
    int i = min(int(x), count - 2);
    return mix(stops[i].rgb, stops[i + 1].rgb, half(x - float(i)));
}

/// The last line of every light-emitting shader: premultiplied output with alpha clamped to `cap`
/// (`Glow.ambientAlphaCap`) and every channel to `Glow.maxBrightness` (0.95).
static inline half4 light(half3 rgb, float alpha, float cap) {
    float a = clamp(alpha, 0.0, cap);
    return half4(half3(min(float3(rgb), 0.95) * a), half(a));
}

} // namespace cranny
