// CrannyEffects/Shaders/Aurora.metal — the "Afterglow" aurora as a SwiftUI stitchable colour effect.
//
// Original work for Cranny (MIT). Three curtains of content colour (the activity's AmbientPalette)
// rise from the bottom edge of the open panel; their upper edges wander with low-frequency noise and
// vertical rays shimmer along them. Contract (DESIGN.md §5.3 and Appendix B):
//   • the top 40 % stays black, so the band merges with the hardware notch;
//   • alpha never exceeds `cap` (= Glow.ambientAlphaCap(level)), the value the contrast audit assumes;
//   • every term is a pure function of (position, time, energy, palette): no state, no feedback;
//   • time comes from a TimelineView that is paused while the panel is closed (zero cost).
// The output is premultiplied, as SwiftUI expects from a colour effect.
#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

namespace cranny {

/// Lattice hash → [0, 1): integer multiply–xorshift avalanche of the cell coordinates.
inline float latticeHash(float2 p) {
    uint2 q = uint2(int2(floor(p)) + int2(40503));
    uint h = q.x * 0x9E3779B1u ^ (q.y * 0x85EBCA77u + 0x632BE5ABu);
    h ^= h >> 15; h *= 0x2C1B3C6Du;
    h ^= h >> 12; h *= 0x297A2D39u;
    h ^= h >> 15;
    return float(h & 0x00FFFFFFu) * (1.0 / 16777216.0);
}

/// Smooth value noise in [0, 1] (quintic fade, so curtains never show creases).
inline float valueNoise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    float2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
    float a = latticeHash(i);
    float b = latticeHash(i + float2(1.0, 0.0));
    float c = latticeHash(i + float2(0.0, 1.0));
    float d = latticeHash(i + float2(1.0, 1.0));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

/// Four octaves of value noise, rotated between octaves so the lattice never lines up. Range ≈ [0, 1].
inline float layeredNoise(float2 p) {
    const float2x2 turn = float2x2(float2(0.8, 0.6), float2(-0.6, 0.8));
    float sum = 0.0;
    float amplitude = 0.5;
    for (int octave = 0; octave < 4; octave++) {
        sum += amplitude * valueNoise(p);
        p = turn * p * 2.07 + float2(13.7, 5.3);
        amplitude *= 0.5;
    }
    return sum / 0.9375;
}

/// Brightness of curtain `index` at `uv` (0…1). Each curtain sits a little lower and moves a little
/// faster than the one before it; louder audio lifts every edge by up to 6 % of the height.
inline float curtain(float2 uv, float aspect, float time, float lift, float index) {
    float x = uv.x * aspect * (1.05 + 0.3 * index);
    float drift = time * (0.032 + 0.014 * index);                    // ≤ 0.05 Hz: calm, never flickers
    float edge = 0.60 + 0.085 * index - lift
               - 0.16 * (layeredNoise(float2(x * 0.85 + drift, index * 4.1)) - 0.5);
    float below = uv.y - edge;
    // Soft fade-in above the edge, slow exponential decay below it.
    float body = smoothstep(-0.13, 0.025, below) * exp(-max(below, 0.0) * (1.5 + 0.45 * index));
    // Rays: narrow, slowly sliding streaks along the curtain.
    float rays = 0.55 + 0.45 * layeredNoise(float2(x * 6.5 + drift * 2.6, uv.y * 1.4 - time * 0.04 + index * 2.3));
    // A low ember along the very bottom edge keeps the floor lit between curtains.
    float floorGlow = smoothstep(0.78, 1.0, uv.y) * (0.34 - 0.08 * index);
    return clamp(body * rays + floorGlow, 0.0, 1.0) * (1.0 - 0.16 * index);
}

} // namespace cranny

/// `position` and `size` are in points (the view's own coordinate space); `color` is the fill below
/// (its alpha masks the light); `cap` is the alpha ceiling; glows are the palette's three light colours.
[[ stitchable ]] half4 crannyAurora(float2 position, half4 color, float2 size, float time, float energy, float cap,
                                    half4 glow1, half4 glow2, half4 glow3) {
    float2 uv = position / max(size, float2(1.0));
    // The band (top 40 %) stays the hardware's black; light fades in over the next 22 %.
    float floorMask = smoothstep(0.40, 0.62, uv.y);
    if (floorMask <= 0.0 || cap <= 0.0) {
        return half4(0.0h);
    }
    float aspect = size.x / max(size.y, 1.0);
    float e = clamp(energy, 0.0, 1.0);
    float lift = 0.06 * e;

    float k1 = cranny::curtain(uv, aspect, time, lift, 0.0);
    float k2 = cranny::curtain(uv, aspect, time, lift, 1.0);
    float k3 = cranny::curtain(uv, aspect, time, lift, 2.0);

    // Hue = weighted mix of the curtains; coverage = union of their light.
    float weight = max(k1 + k2 + k3, 1e-4);
    float3 hue = (float3(glow1.rgb) * k1 + float3(glow2.rgb) * k2 + float3(glow3.rgb) * k3) / weight;
    float coverage = 1.0 - (1.0 - k1) * (1.0 - k2) * (1.0 - k3);

    float alpha = min(coverage * floorMask * cap * (0.8 + 0.2 * e), cap) * float(color.a);
    return half4(half3(hue * alpha), half(alpha));
}
