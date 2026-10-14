// CrannyEffects/Shaders/Dither.metal — the shared last pass of every gradient-producing effect (DESIGN.md §5.6).
#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
#include "CrannyShaders.h"
using namespace metal;

/// Adds ±amount/2 LSB of 8-bit interleaved-gradient noise to premultiplied colour so that dim gradients over
/// black do not band. `scale` is the display scale (noise per pixel, not per point). Transparent stays transparent.
[[ stitchable ]] half4 crannyDither(float2 position, half4 color, float amount, float scale) {
    if (color.a <= 0.0h) { return color; }
    float n = (cranny::ign(floor(position * scale)) - 0.5) * amount / 255.0;
    float a = float(color.a);
    return half4(half3(clamp(float3(color.rgb) + n, 0.0, a)), color.a);
}
