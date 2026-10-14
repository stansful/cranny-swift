// CrannyEffects/Shaders/ChargeSweep.metal — Charger connected (DESIGN.md §5.5, §5.6 `chargeSweep`): a green head
// with a fading tail sweeps along the lower outline. Fallback: a `trim` of the same path (ChargeSweep.swift).
#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
#include "CrannyShaders.h"
using namespace metal;

/// `.colorEffect` on the rim stroke. `bounds` is the outline's bounding box (the lower outline is x-monotonic, so
/// u = (x − minX) / width stands in for arc length); `progress` runs 0 → 1 over 0.8 s. The stroke's own coverage
/// (`color.a`) masks the light. Swift: `.float4(rect), .float(progress), .color(glow), .float(cap)`.
[[ stitchable ]] half4 chargeSweep(float2 position, half4 color, float4 bounds, float progress, half4 glow, float cap) {
    if (color.a <= 0.0h) { return half4(0.0h); }
    float u = (position.x - bounds.x) / max(bounds.z, 1.0);
    float t = clamp(progress, 0.0, 1.0);
    float eased = t * t * (3.0 - 2.0 * t);                                      // easeInOut
    float s = eased * 1.2 - 0.1;                                                // the head, leading → trailing
    float head = exp(-((u - s) / 0.05) * ((u - s) / 0.05));
    float tail = u <= s ? 0.45 * smoothstep(s - 0.30, s, u) : 0.0;
    float out = 1.0 - smoothstep(0.85, 1.0, t);                                 // no pop when the view goes
    return cranny::light(glow.rgb, cap * float(color.a) * (head + tail) * out, cap);
}
