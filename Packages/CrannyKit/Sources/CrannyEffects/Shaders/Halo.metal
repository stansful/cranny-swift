// CrannyEffects/Shaders/Halo.metal — one static bloom (DESIGN.md §5.6 `haloGlow`). Used by First light and by
// callers that ask for `.halo` while shaders are allowed. The automatic Low Power halo is the RadialGradient fallback.
#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
#include "CrannyShaders.h"
using namespace metal;

namespace cranny {

/// Gaussian radial falloff: alpha 0.6 · cap · exp(−2.8 · (d / R)²), no crease where a gradient would end.
static inline half4 halo(float2 p, float2 size, float2 center, float radius, half3 glow, float cap) {
    float x = length(p - center * size) / max(radius, 1.0);
    return light(glow, 0.6 * cap * exp(-2.8 * x * x), cap);
}

} // namespace cranny

/// SwiftUI path. `center` is a unit point in `bounds`, `radius` in points.
/// Swift: `.boundingRect, .float2(center), .float(radius), .color(glow), .float(cap)`.
[[ stitchable ]] half4 haloGlow(float2 position, half4 color, float4 bounds, float2 center, float radius,
                                half4 glow, float cap) {
    return cranny::halo(position - bounds.xy, bounds.zw, center, radius, glow.rgb, cap);
}

/// The ambient Metal layer (AmbientRenderer): glow = the first stop, centre and radius from `halo`.
fragment half4 haloFragment(cranny::AmbientVertexOut in [[stage_in]],
                            constant cranny::AmbientUniforms &u [[buffer(0)]]) {
    cranny::AmbientPixel px = cranny::ambientPixel(in, u);
    float m = cranny::ambientMask(px, u);
    if (m <= 0.0) { return half4(0.0h); }                                       // masked out: nothing to evaluate
    half4 c = cranny::halo(px.position, px.size, u.halo.xy, u.halo.z, cranny::stop(px.palette, 0), u.params.z);
    return cranny::ambientFinish(c, px, u, m);
}
