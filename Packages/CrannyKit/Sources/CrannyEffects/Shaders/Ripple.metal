// CrannyEffects/Shaders/Ripple.metal — the song-change ripple (DESIGN.md §5.6 `songRipple`). A distortion of
// the ambient light only, for 0.6 s after a track change. The ambient Metal layer applies the same
// `cranny::rippleSource` before it evaluates its field.
#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
#include "CrannyShaders.h"
using namespace metal;

/// `.distortionEffect`: where each pixel samples from. `center` is the camera (top centre, in points), `time`
/// the seconds since the trigger. Swift: `.float2(center), .float(t), .float(6), .float(56), .float(480)`.
[[ stitchable ]] float2 songRipple(float2 position, float2 center, float time, float amplitude, float wavelength,
                                   float speed) {
    return cranny::rippleSource(position, center, time, amplitude, wavelength, speed);
}
