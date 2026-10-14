// CrannyEffects/Shaders/Aurora.metal — the signature effect (DESIGN.md §5.6). Fallback: AuroraField's SwiftUI path (App. B.1).
#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
#include "CrannyShaders.h"
using namespace metal;

namespace cranny {

/// Four palette stops (indices modulo the stop count) spread over x in 0…1, interpolated in OKLab.
static inline float3 band(thread const Palette &pal, float x, int4 order) {
    float s = clamp(x, 0.0, 1.0) * 3.0;
    int i = min(int(s), 2);
    return mix(oklab(stop(pal, order[i])), oklab(stop(pal, order[i + 1])), s - float(i));
}

/// Domain-warped fBm curtains rising from the bottom edge, coloured by the palette stops. `p` and `size` are in
/// points; the top 40 % returns clear, so the band stays black.
static inline half4 aurora(float2 p, float2 size, float time, thread const Palette &pal,
                           float energy, float intensity, float cap) {
    float2 uv = p / max(size, float2(1.0));
    if (uv.y <= 0.40) { return half4(0.0h); }                                    // the band stays black
    float2 d = float2(uv.x * size.x / max(size.y, 1.0) * 1.2, uv.y * 0.5);      // anisotropic: tall curtains
    float2 q = float2(fbm(d + float2(0.0, 0.05 * time), 3),
                      fbm(d + float2(5.2, 1.3) - float2(0.04 * time, 0.0), 3));
    float2 r = float2(fbm(d + 1.5 * intensity * q + float2(1.7, 9.2) + 0.07 * time, 3),
                      fbm(d + 1.5 * intensity * q + float2(8.3, 2.8) - 0.06 * time, 3));
    float f = smoothstep(0.25, 0.75, fbm(d + 2.0 * r, 4));
    float rays = 0.55 + 0.45 * smoothstep(0.3, 0.7, fbm(float2(5.0 * d.x + 1.5 * r.y, 0.08 * time), 3));
    // Envelope like the fallback mesh's: alpha rises from the band (0 at 40 %, eased in over 4 %) and reaches its
    // ceiling by 80 % of the height; louder audio lifts it by up to 6 %. Toward the bottom edge the curtains melt
    // into their bright base (60 % uniform glow), so the bottom third is as full as the mesh's.
    float t = clamp((uv.y - 0.40 + 0.06 * energy) / 0.40, 0.0, 1.0);
    float envelope = (1.0 - (1.0 - t) * (1.0 - t)) * smoothstep(0.40, 0.44, uv.y);
    float structure = mix(rays * mix(0.45, 1.0, f), 1.0, 0.6 * smoothstep(0.50, 1.0, uv.y));
    // Colour follows the fallback mesh's layout (DESIGN.md App. B.1), warped by the folds, mixed in OKLab like the
    // mesh: along the bottom edge stop 3 · 1 · 2 · 3 from left to right, 1 · 2 · 3 · 1 in the row above.
    float x = uv.x + 0.20 * (q.x - 0.5) + 0.16 * (f - 0.5);
    float3 lab = mix(band(pal, x, int4(0, 1, 2, 0)), band(pal, x, int4(2, 0, 1, 2)), smoothstep(0.60, 0.95, uv.y));
    return light(fromOklab(lab), cap * (0.8 + 0.2 * energy) * envelope * structure, cap);
}

} // namespace cranny

/// SwiftUI path. Swift: `.boundingRect, .float(time), .colorArray(glows), .float(energy), .float(level.intensity), .float(cap)`.
[[ stitchable ]] half4 auroraField(float2 position, half4 color, float4 bounds, float time,
                                   device const half4 *stops, int stopCount,
                                   float energy, float intensity, float cap) {
    cranny::Palette pal = cranny::palette(stops, stopCount);
    return cranny::aurora(position - bounds.xy, bounds.zw, time, pal, energy, intensity, cap);
}

/// The ambient Metal layer (AmbientRenderer): the same field, plus fill, reveal, ripple and dither.
fragment half4 auroraFragment(cranny::AmbientVertexOut in [[stage_in]],
                              constant cranny::AmbientUniforms &u [[buffer(0)]]) {
    cranny::AmbientPixel px = cranny::ambientPixel(in, u);
    half4 c = cranny::aurora(px.position, px.size, u.frame.w, px.palette, u.params.x, u.params.y, u.params.z);
    return cranny::ambientFinish(c, px, u);
}
