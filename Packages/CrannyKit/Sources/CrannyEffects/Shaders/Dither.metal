// CrannyEffects/Shaders/Dither.metal — the shared last pass of every gradient-producing effect (DESIGN.md §5.6).
#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
#include "CrannyShaders.h"
using namespace metal;

/// Adds ±amount/2 LSB of 8-bit interleaved-gradient noise to premultiplied colour so that dim gradients over
/// black do not band. `scale` is the display scale (noise per pixel, not per point). Transparent stays transparent.
/// The ambient Metal layer applies the same `cranny::dither` inside its fragment functions.
[[ stitchable ]] half4 crannyDither(float2 position, half4 color, float amount, float scale) {
    return cranny::dither(color, position * scale, amount);
}
