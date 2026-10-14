// CrannyEffects/Shaders/Ember.metal — Timer done (DESIGN.md §5.5, §5.6 `emberBurst`): 18 stateless embers fan
// out of the notch for 0.9 s. Fallback: EmberBurst's Canvas (EmberBurst.swift, same `EmberMath`).
#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
#include "CrannyShaders.h"
using namespace metal;

namespace cranny {

/// Where ember `i` is `t` seconds after the burst: a direction within ±75° of straight down, 120–260 pt/s,
/// drag (distance v · (1 − e^(−2.6t)) / 2.6) and 60 pt/s² of gravity, so the burst fans out ≈ 90 pt and droops.
/// Mirrors `EmberMath.position`.
static inline float2 emberPosition(uint i, float2 origin, float t) {
    float angle = (-75.0 + 150.0 * hash(i + 18U)) * M_PI_F / 180.0;
    float speed = 120.0 + 140.0 * hash(i + 36U);
    float travel = speed * (1.0 - exp(-2.6 * t)) / 2.6;
    return origin + float2(sin(angle), cos(angle)) * travel + float2(0.0, 30.0 * t * t);
}

/// Distance from `p` to the segment a–b.
static inline float segmentDistance(float2 p, float2 a, float2 b) {
    float2 ab = b - a;
    float h = clamp(dot(p - a, ab) / max(dot(ab, ab), 1e-6), 0.0, 1.0);
    return length(p - a - ab * h);
}

static inline half4 embers(float2 p, float2 origin, float time, thread const Palette &pal, float cap) {
    float3 rgb = float3(0.0);
    float alpha = 0.0;
    for (uint i = 0; i < 18U; i++) {
        float life = 0.55 + 0.35 * hash(i + 72U);                              // 0.55–0.9 s
        if (time >= life) { continue; }
        float2 head = emberPosition(i, origin, time);
        float2 tail = emberPosition(i, origin, max(time - 0.05, 0.0));          // a 0.05-s capsule along the path
        float radius = 1.2 + 1.4 * hash(i + 54U);                               // 1.2–2.6 pt
        float d = segmentDistance(p, tail, head);
        if (d > 9.0 * radius) { continue; }
        float x = d / radius, y = d / (3.0 * radius);
        float profile = exp(-x * x) + 0.4 * exp(-y * y);
        float fade = (1.0 - time / life) * (1.0 - time / life);
        float flicker = 0.75 + 0.25 * sin(19.0 * time + 6.2831853 * hash(i));
        float a = cap * fade * flicker * profile;
        rgb += float3(stop(pal, int(hash(i + 90U) * float(max(pal.count, 1))))) * a;
        alpha += a;
    }
    if (alpha <= 0.0) { return half4(0.0h); }
    return light(half3(rgb / alpha), alpha, cap);
}

} // namespace cranny

/// Swift: `.boundingRect, .float2(origin), .float(t), .colorArray(timer glows), .float(cap)`. `origin` is in the
/// view's coordinates (the shape's bottom edge under the camera), `time` 0…0.9 s since the trigger.
[[ stitchable ]] half4 emberBurst(float2 position, half4 color, float4 bounds, float2 origin, float time,
                                  device const half4 *stops, int stopCount, float cap) {
    cranny::Palette pal = cranny::palette(stops, stopCount);
    return cranny::embers(position - bounds.xy, origin, time, pal, cap);
}
