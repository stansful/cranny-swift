// CrannyEffects/Shaders/Aurora.metal — the signature effect (DESIGN.md §5.6). Fallback: AuroraField's SwiftUI path (App. B.1).
#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
#include "CrannyShaders.h"
using namespace metal;

/// Domain-warped fBm curtains rising from the bottom edge, coloured by the palette stops.
/// Swift: `.boundingRect, .float(time), .colorArray(glows), .float(energy), .float(level.intensity), .float(cap)`.
[[ stitchable ]] half4 auroraField(float2 position, half4 color, float4 bounds, float time,
                                   device const half4 *stops, int stopCount,
                                   float energy, float intensity, float cap) {
    float2 uv = (position - bounds.xy) / max(bounds.zw, float2(1.0));
    if (uv.y <= 0.40) { return half4(0.0h); }                       // the band stays black
    float2 p = float2(uv.x * bounds.z / max(bounds.w, 1.0) * 1.2, uv.y * 0.5);   // anisotropic: tall curtains
    float2 q = float2(cranny::fbm(p + float2(0.0, 0.05 * time), 3),
                      cranny::fbm(p + float2(5.2, 1.3) - float2(0.04 * time, 0.0), 3));
    float2 r = float2(cranny::fbm(p + 1.5 * intensity * q + float2(1.7, 9.2) + 0.07 * time, 3),
                      cranny::fbm(p + 1.5 * intensity * q + float2(8.3, 2.8) - 0.06 * time, 3));
    float f = smoothstep(0.25, 0.75, cranny::fbm(p + 2.0 * r, 4));
    float rays = 0.55 + 0.45 * smoothstep(0.3, 0.7, cranny::fbm(float2(5.0 * p.x + 1.5 * r.y, 0.08 * time), 3));
    float rise = smoothstep(0.40, 0.78 - (0.08 + 0.06 * energy), uv.y);  // louder audio lifts the light ≤ 6 %
    half3 rgb = cranny::ramp(stops, stopCount, 0.15 + 0.7 * f + 0.3 * (q.x - 0.5));
    return cranny::light(rgb, cap * (0.8 + 0.2 * energy) * rise * rays * mix(0.45, 1.0, f), cap);
}
