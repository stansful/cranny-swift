// CrannyEffects/Shaders/Tide.metal — luminous wave lines along the bottom edge (DESIGN.md §5.3, §5.6 `tideField`).
// Fallback: TideField's Canvas (TideField.swift, same `TideMath`).
#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
#include "CrannyShaders.h"
using namespace metal;

namespace cranny {

/// Three soft, tapered sine lines (line i in stop i) with a 3-pt bloom, summed additively. Points throughout. A pixel
/// evaluates only the lines that can reach it (one or two).
static inline half4 tide(float2 p, float2 size, float time, thread const Palette &pal,
                         float energy, float intensity, float cap) {
    float width = max(size.x, 1.0), height = max(size.y, 1.0);
    float amplitude0 = 3.0 + 7.0 * energy;
    if (p.y < 0.80 * height - 1.45 * amplitude0 - 10.0) { return half4(0.0h); }  // above every line and bloom
    float u = clamp(p.x / width, 0.0, 1.0);
    float taper = pow(sin(M_PI_F * u), 0.6);                                    // thin and fade toward both ends
    if (taper <= 1e-3) { return half4(0.0h); }
    float3 rgb = float3(0.0);
    float alpha = 0.0;
    for (int i = 0; i < 3; i++) {
        float fi = float(i);
        float base = height * (0.80 + 0.06 * fi);
        float amplitude = amplitude0 * (1.0 - 0.2 * fi);
        float k = 2.0 * M_PI_F * (0.75 + 0.35 * fi) / width;
        // A line strays at most 1.45 · amplitude from its base, with a slope of at most 1.855 · amplitude · k: farther
        // than that plus 10 slope-corrected points, its core is 0 and its bloom ≤ 0.35 · e⁻¹¹ (< 0.001 LSB). Skip it.
        float slopeMax = 1.855 * abs(amplitude) * k;
        if (abs(p.y - base) > 1.45 * abs(amplitude) + 10.0 * sqrt(1.0 + slopeMax * slopeMax)) { continue; }
        float omega = 2.0 * M_PI_F * (0.09 + 0.035 * fi);
        float a1 = k * p.x + omega * time + 2.1 * fi;
        float a2 = 1.9 * k * p.x - 1.4 * omega * time;
        float y = base + amplitude * (sin(a1) + 0.45 * sin(a2));
        float slope = amplitude * k * (cos(a1) + 0.855 * cos(a2));
        float d = abs(p.y - y) / sqrt(1.0 + slope * slope);                     // slope-corrected distance
        float core = 1.0 - smoothstep(0.5 * taper, 1.25 * taper, d);
        float bloom = 0.35 * exp(-(d / 3.0) * (d / 3.0));
        float a = cap * (0.55 + 0.45 * intensity) * (core + bloom) * taper;
        rgb += float3(stop(pal, i)) * a;
        alpha += a;
    }
    if (alpha <= 0.0) { return half4(0.0h); }
    return light(half3(rgb / alpha), alpha, cap);
}

} // namespace cranny

/// SwiftUI path. Swift: `.boundingRect, .float(time), .colorArray(glows), .float(energy), .float(level.intensity), .float(cap)`.
[[ stitchable ]] half4 tideField(float2 position, half4 color, float4 bounds, float time,
                                 device const half4 *stops, int stopCount,
                                 float energy, float intensity, float cap) {
    cranny::Palette pal = cranny::palette(stops, stopCount);
    return cranny::tide(position - bounds.xy, bounds.zw, time, pal, energy, intensity, cap);
}

/// The ambient Metal layer (AmbientRenderer).
fragment half4 tideFragment(cranny::AmbientVertexOut in [[stage_in]],
                            constant cranny::AmbientUniforms &u [[buffer(0)]]) {
    cranny::AmbientPixel px = cranny::ambientPixel(in, u);
    float m = cranny::ambientMask(px, u);
    if (m <= 0.0) { return half4(0.0h); }                                       // masked out: nothing to evaluate
    half4 c = cranny::tide(px.position, px.size, u.frame.w, px.palette, u.params.x, u.params.y, u.params.z);
    return cranny::ambientFinish(c, px, u, m);
}
