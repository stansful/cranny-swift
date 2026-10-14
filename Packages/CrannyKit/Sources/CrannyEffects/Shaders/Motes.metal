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

/// A pixel evaluates only the 9 motes of its own and the two neighbouring columns.
static inline half4 motes(float2 p, float2 size, float time, thread const Palette &pal,
                          float energy, float intensity, float cap) {
    float2 s = max(size, float2(1.0));
    float v = p.y / s.y;
    if (v <= 0.40) { return half4(0.0h); }                                      // faded out in the top 40 %
    float fade = smoothstep(0.40, 0.60, v);
    int column = int(floor(p.x / (s.x / 12.0)));
    float3 rgb = float3(0.0);
    float alpha = 0.0;
    for (int c = column - 1; c <= column + 1; c++) {
        if (c < 0 || c > 11) { continue; }
        for (int j = 0; j < 3; j++) {
            Mote m = mote(c, j, s, time, energy);
            float d = length(p - m.center);
            float x = d / m.radius, y = d / (3.0 * m.radius);
            float profile = exp(-x * x) + 0.25 * exp(-y * y);
            float a = cap * (0.6 + 0.4 * intensity) * profile * m.twinkle;
            rgb += float3(stop(pal, c * 3 + j)) * a;
            alpha += a;
        }
    }
    if (alpha <= 0.0) { return half4(0.0h); }
    return light(half3(rgb / alpha), alpha * fade, cap);
}

} // namespace cranny

/// SwiftUI path. Swift: `.boundingRect, .float(time), .colorArray(glows), .float(energy), .float(level.intensity), .float(cap)`.
[[ stitchable ]] half4 motesField(float2 position, half4 color, float4 bounds, float time,
                                  device const half4 *stops, int stopCount,
                                  float energy, float intensity, float cap) {
    cranny::Palette pal = cranny::palette(stops, stopCount);
    return cranny::motes(position - bounds.xy, bounds.zw, time, pal, energy, intensity, cap);
}

/// The ambient Metal layer (AmbientRenderer).
fragment half4 motesFragment(cranny::AmbientVertexOut in [[stage_in]],
                             constant cranny::AmbientUniforms &u [[buffer(0)]]) {
    cranny::AmbientPixel px = cranny::ambientPixel(in, u);
    half4 c = cranny::motes(px.position, px.size, u.frame.w, px.palette, u.params.x, u.params.y, u.params.z);
    return cranny::ambientFinish(c, px, u);
}
