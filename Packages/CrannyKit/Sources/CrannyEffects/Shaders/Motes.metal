// CrannyEffects/Shaders/Motes.metal — slow rising specks that twinkle (DESIGN.md §5.3, §5.6 `motesField`).
// Fallback: MotesField's Canvas (MotesField.swift, same `MoteMath`).
#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
#include "CrannyShaders.h"
using namespace metal;

namespace cranny {

/// One of the 36 stateless motes (12 columns × 3), seeded by `hash(column · 3 + j)`. Mirrors `MoteMath.mote`.
struct Mote {
    float2 center;     // points
    float radius;      // points
    float twinkle;     // 0.55 … 1
};

static inline Mote mote(int column, int j, float2 size, float time, float energy) {
    uint n = uint(column * 3 + j);
    float h0 = hash(n), h1 = hash(n + 36U), h2 = hash(n + 72U), h3 = hash(n + 108U), h4 = hash(n + 144U),
          h5 = hash(n + 180U);
    float columnWidth = size.x / 12.0;
    float speed = 5.0 + 9.0 * h2;                                               // 5–14 pt/s
    const float margin = 8.0;
    float span = size.y + 2.0 * margin;
    float travel = speed * time + 0.6 * energy * speed;                         // louder audio lifts them
    Mote m;
    m.center = float2((float(column) + 0.5 + (h0 - 0.5) * 0.6) * columnWidth + 4.0 * sin(0.6 * time + 6.2831853 * h1),
                      size.y + margin - fmod(h3 * span + travel, span));        // rises, wraps below the bottom
    m.radius = 0.8 + 1.6 * h4;                                                  // 0.8–2.4 pt
    float frequency = 1.2 + 2.0 * h5;                                           // 1.2–3.2 Hz
    m.twinkle = 1.0 - 0.45 * (0.5 + 0.5 * sin(2.0 * M_PI_F * frequency * time + 6.2831853 * h0));
    return m;
}

/// Adds one mote's light at `p`. Beyond 9 radii it adds nothing: the skirt there is 0.25 · e⁻⁹ ≈ 3e-5 of the peak,
/// and nine such motes stay below 0.04 LSB (motes are not dithered).
static inline void addMote(float2 p, Mote m, half3 color, float strength, thread float3 &rgb, thread float &alpha) {
    float d = length(p - m.center);
    if (d > 9.0 * m.radius) { return; }
    float x = d / m.radius, y = d / (3.0 * m.radius);
    float profile = exp(-x * x) + 0.25 * exp(-y * y);
    float a = strength * profile * m.twinkle;
    rgb += float3(color) * a;
    alpha += a;
}

/// The field's top fade and final light, shared by both entry points: faded out in the top 40 %.
static inline half4 motesLight(float3 rgb, float alpha, float v, float cap) {
    if (alpha <= 0.0) { return half4(0.0h); }
    return light(half3(rgb / alpha), alpha * smoothstep(0.40, 0.60, v), cap);
}

/// A pixel evaluates only the 9 motes of its own and the two neighbouring columns (SwiftUI path: each mote from its
/// hashes, per pixel).
static inline half4 motes(float2 p, float2 size, float time, thread const Palette &pal,
                          float energy, float intensity, float cap) {
    float2 s = max(size, float2(1.0));
    float v = p.y / s.y;
    if (v <= 0.40) { return half4(0.0h); }                                      // faded out in the top 40 %
    int column = int(floor(p.x / (s.x / 12.0)));
    float strength = cap * (0.6 + 0.4 * intensity);
    float3 rgb = float3(0.0);
    float alpha = 0.0;
    for (int c = column - 1; c <= column + 1; c++) {
        if (c < 0 || c > 11) { continue; }
        for (int j = 0; j < 3; j++) {
            addMote(p, mote(c, j, s, time, energy), stop(pal, c * 3 + j), strength, rgb, alpha);
        }
    }
    return motesLight(rgb, alpha, v, cap);
}

/// The same field from the frame's 36 motes, computed once per frame on the CPU (`AmbientFrameTables.motes`):
/// entry 2k is mote k's (centre x, y, radius, twinkle), entry 2k + 1 its stop colour (rgb), k = column · 3 + j.
static inline half4 motes(float2 p, float2 size, constant float4 *table, float intensity, float cap) {
    float2 s = max(size, float2(1.0));
    float v = p.y / s.y;
    if (v <= 0.40) { return half4(0.0h); }                                      // faded out in the top 40 %
    int column = int(floor(p.x / (s.x / 12.0)));
    float strength = cap * (0.6 + 0.4 * intensity);
    float3 rgb = float3(0.0);
    float alpha = 0.0;
    for (int c = column - 1; c <= column + 1; c++) {
        if (c < 0 || c > 11) { continue; }
        for (int j = 0; j < 3; j++) {
            int k = c * 3 + j;
            float4 entry = table[2 * k];
            Mote m;
            m.center = entry.xy;
            m.radius = entry.z;
            m.twinkle = entry.w;
            addMote(p, m, half3(table[2 * k + 1].rgb), strength, rgb, alpha);
        }
    }
    return motesLight(rgb, alpha, v, cap);
}

} // namespace cranny

/// SwiftUI path. Swift: `.boundingRect, .float(time), .colorArray(glows), .float(energy), .float(level.intensity), .float(cap)`.
[[ stitchable ]] half4 motesField(float2 position, half4 color, float4 bounds, float time,
                                  device const half4 *stops, int stopCount,
                                  float energy, float intensity, float cap) {
    cranny::Palette pal = cranny::palette(stops, stopCount);
    return cranny::motes(position - bounds.xy, bounds.zw, time, pal, energy, intensity, cap);
}

/// The ambient Metal layer (AmbientRenderer): the motes of this frame come from `buffer(1)`.
fragment half4 motesFragment(cranny::AmbientVertexOut in [[stage_in]],
                             constant cranny::AmbientUniforms &u [[buffer(0)]],
                             constant float4 *table [[buffer(1)]]) {
    cranny::AmbientPixel px = cranny::ambientPixel(in, u);
    float m = cranny::ambientMask(px, u);
    if (m <= 0.0) { return half4(0.0h); }                                       // masked out: nothing to evaluate
    half4 c = cranny::motes(px.position, px.size, table, u.params.y, u.params.z);
    return cranny::ambientFinish(c, px, u, m);
}
