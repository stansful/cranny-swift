// CrannyEffects/Shaders/CrannyShaders.h — helpers shared by the CrannyEffects shaders (DESIGN.md §5.6).
// `#include "CrannyShaders.h"` resolves next to the .metal files; SwiftPM does not copy the header.
//
// Every effect is written once, as a `static inline` field function of (position in points, size, time,
// palette, …), and called from two entry points in the same file:
//   * a SwiftUI `[[ stitchable ]]` function (`.colorEffect`, `.layerEffect`, `.distortionEffect`), and
//   * for the ambient effects, a `[[ fragment ]]` function of the dedicated Metal layer (`AmbientRenderer`),
//     which draws the light without invalidating SwiftUI on every frame (ARCHITECTURE.md §10.1, issue 1).
#pragma once
#include <metal_stdlib>
using namespace metal;

namespace cranny {

/// Interleaved gradient noise (Jimenez 2014) in 0..<1: a cheap, texture-free stand-in for blue noise.
static inline float ign(float2 pixel) {
    return fract(52.9829189 * fract(dot(pixel, float2(0.06711056, 0.00583715))));
}

/// Stateless integer hash in 0...1 (seeds noise lattices and particles; nothing keeps per-particle state).
/// `StatelessHash.hash` (Swift) is the same function, for the Canvas fallbacks.
static inline float hash(uint n) {
    n = (n << 13U) ^ n;
    n = n * (n * n * 15731U + 789221U) + 1376312589U;
    return float(n & 0x7fffffffU) / float(0x7fffffffU);
}
static inline float hash21(float2 lattice) {
    int2 i = int2(floor(lattice));
    return hash(uint(i.x) * 1597334677U ^ uint(i.y) * 3812015801U);
}

/// Smooth value noise in 0...1.
static inline float valueNoise(float2 p) {
    float2 i = floor(p), f = fract(p);
    float2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash21(i), hash21(i + float2(1, 0)), u.x),
               mix(hash21(i + float2(0, 1)), hash21(i + float2(1, 1)), u.x), u.y);
}

/// Fractal Brownian motion: `octaves` of value noise (lacunarity 2, gain 0.5), normalised to 0...1.
static inline float fbm(float2 p, int octaves) {
    float sum = 0.0, amplitude = 0.5, norm = 0.0;
    for (int i = 0; i < octaves; i++) {
        sum += amplitude * valueNoise(p);
        norm += amplitude;
        p = p * 2.0 + float2(17.0, 9.0);
        amplitude *= 0.5;
    }
    return sum / max(norm, 1e-4);
}

/// Piecewise-linear ramp through the palette stops (`.colorArray`, 1–5 entries), t in 0...1.
static inline half3 ramp(device const half4 *stops, int count, float t) {
    if (count <= 1) { return count == 1 ? stops[0].rgb : half3(0.0h); }
    float x = clamp(t, 0.0, 1.0) * float(count - 1);
    int i = min(int(x), count - 2);
    return mix(stops[i].rgb, stops[i + 1].rgb, half(x - float(i)));
}

/// The last line of every light-emitting shader: premultiplied output with alpha clamped to `cap`
/// (`Glow.ambientAlphaCap`) and every channel to `Glow.maxBrightness` (0.95).
static inline half4 light(half3 rgb, float alpha, float cap) {
    float a = clamp(alpha, 0.0, cap);
    return half4(half3(min(float3(rgb), 0.95) * a), half(a));
}

// MARK: - Palette (the same stops from SwiftUI's `.colorArray` or from the layer's uniforms)

/// Up to five palette stops in a thread-local copy, so one field function serves both entry points.
struct Palette {
    half3 colors[5];
    int count;
};

static inline Palette palette(device const half4 *stops, int count) {
    Palette p;
    p.count = clamp(count, 0, 5);
    for (int i = 0; i < 5; i++) { p.colors[i] = i < p.count ? stops[i].rgb : half3(0.0h); }
    return p;
}

static inline Palette palette(constant float4 *stops, int count) {
    Palette p;
    p.count = clamp(count, 0, 5);
    for (int i = 0; i < 5; i++) { p.colors[i] = i < p.count ? half3(stops[i].rgb) : half3(0.0h); }
    return p;
}

/// `ramp` over a `Palette`.
static inline half3 ramp(thread const Palette &p, float t) {
    if (p.count <= 1) { return p.count == 1 ? p.colors[0] : half3(0.0h); }
    float x = clamp(t, 0.0, 1.0) * float(p.count - 1);
    int i = min(int(x), p.count - 2);
    return mix(p.colors[i], p.colors[i + 1], half(x - float(i)));
}

/// Stop `i` modulo the stop count (lines, motes and embers pick one stop each).
static inline half3 stop(thread const Palette &p, int i) {
    return p.count > 0 ? p.colors[i % p.count] : half3(0.0h);
}

// MARK: - Perceptual mixing (like MeshGradient's `.perceptual` colour space)

static inline float3 srgbToLinear(float3 c) {
    return select(pow((c + 0.055) / 1.055, float3(2.4)), c / 12.92, c <= 0.04045);
}
static inline float3 linearToSrgb(float3 c) {
    c = max(c, 0.0);
    return select(1.055 * pow(c, float3(1.0 / 2.4)) - 0.055, c * 12.92, c <= 0.0031308);
}

/// sRGB-encoded colour → OKLab (Ottosson 2020).
static inline float3 oklab(half3 srgb) {
    float3 c = srgbToLinear(float3(srgb));
    float3 lms = float3(0.4122214708 * c.r + 0.5363325363 * c.g + 0.0514459929 * c.b,
                        0.2119034982 * c.r + 0.6806995451 * c.g + 0.1073969566 * c.b,
                        0.0883024619 * c.r + 0.2817188376 * c.g + 0.6299787005 * c.b);
    lms = sign(lms) * pow(abs(lms), float3(1.0 / 3.0));
    return float3(0.2104542553 * lms.x + 0.7936177850 * lms.y - 0.0040720468 * lms.z,
                  1.9779984951 * lms.x - 2.4285922050 * lms.y + 0.4505937099 * lms.z,
                  0.0259040371 * lms.x + 0.7827717662 * lms.y - 0.8086757660 * lms.z);
}

/// OKLab → sRGB-encoded colour.
static inline half3 fromOklab(float3 lab) {
    float3 lms = float3(lab.x + 0.3963377774 * lab.y + 0.2158037573 * lab.z,
                        lab.x - 0.1055613458 * lab.y - 0.0638541728 * lab.z,
                        lab.x - 0.0894841775 * lab.y - 1.2914855480 * lab.z);
    lms = lms * lms * lms;
    float3 c = float3( 4.0767416621 * lms.x - 3.3077115913 * lms.y + 0.2309699292 * lms.z,
                      -1.2684380046 * lms.x + 2.6097574011 * lms.y - 0.3413193965 * lms.z,
                      -0.0041960863 * lms.x - 0.7034186147 * lms.y + 1.7076147010 * lms.z);
    return half3(clamp(linearToSrgb(c), 0.0, 1.0));
}

// MARK: - Shared passes

/// ±amount/2 LSB of 8-bit interleaved-gradient noise on premultiplied colour (`crannyDither`'s body).
/// `pixel` is in device pixels. Transparent stays transparent; colour never exceeds alpha.
static inline half4 dither(half4 color, float2 pixel, float amount) {
    if (color.a <= 0.0h) { return color; }
    float n = (ign(floor(pixel)) - 0.5) * amount / 255.0;
    float a = float(color.a);
    return half4(half3(clamp(float3(color.rgb) + n, 0.0, a)), color.a);
}

/// The song-change ripple (DESIGN.md §5.6 `songRipple`): the position a pixel samples from, `t` seconds
/// after the trigger. A radial wave from `center` that fades out over 0.6 s.
static inline float2 rippleSource(float2 p, float2 center, float t, float amplitude, float wavelength, float speed) {
    if (t <= 0.0 || t >= 0.6) { return p; }
    float2 d = p - center;
    float r = length(d);
    if (r < 1e-3) { return p; }
    float x = (r - speed * t) / max(wavelength, 1e-3);
    float fade = 1.0 - t / 0.6;
    float w = amplitude * sin(2.0 * M_PI_F * x) * exp(-x * x) * fade * fade;
    return p - (d / r) * w;
}

/// The ambient fill (`ambientIn` / `ambientOut`): the light rises from the bottom edge. `v` is the
/// vertical position in 0 (top) … 1 (bottom); `fill` 0 shows nothing, 1 everything; 25 % soft edge.
static inline float fillMask(float v, float fill) {
    const float soft = 0.25;
    float edge = 1.0 - clamp(fill, 0.0, 1.0) * (1.0 + soft);
    return smoothstep(edge, edge + soft, v);
}

/// First light's reveal: 1 inside `radius − feather`, 0 beyond `radius` (points). radius < 0 = no reveal.
static inline float revealMask(float2 p, float4 reveal) {
    if (reveal.z < 0.0) { return 1.0; }
    float feather = max(reveal.w, 1e-3);
    return 1.0 - smoothstep(reveal.z - feather, reveal.z, length(p - reveal.xy));
}

// MARK: - The ambient Metal layer (AmbientRenderer.swift mirrors this layout as `AmbientUniforms`)

/// Uniforms of the ambient layer's fragment functions. Every member is a 16-byte vector, so the Swift
/// mirror has the same layout on arm64 and x86_64 (176 bytes).
struct AmbientUniforms {
    float4 frame;     // width, height (pt), scale (pixels per pt), time (s, mod 3600)
    float4 params;    // energy, intensity, cap, fill
    float4 reveal;    // centre x, y (pt), radius, feather (pt); radius < 0 = no reveal
    float4 ripple;    // centre x, y (pt), seconds since the trigger, 1 = playing
    float4 halo;      // centre x, y (unit point), radius (pt), dither amount (1 = ±0.5 LSB)
    float4 stops[5];  // palette stops, sRGB, alpha unused
    int4 counts;      // stop count, unused, unused, unused
};

struct AmbientVertexOut {
    float4 position [[position]];
};

/// What every ambient fragment works on: the position in points (after the ripple), the size, the palette.
struct AmbientPixel {
    float2 position;   // points, top-left origin, ripple applied
    float2 size;       // points
    float2 pixel;      // device pixels (for the dither and the masks)
    Palette palette;
};

static inline AmbientPixel ambientPixel(AmbientVertexOut in, constant AmbientUniforms &u) {
    AmbientPixel px;
    px.pixel = in.position.xy;
    px.size = max(u.frame.xy, float2(1.0));
    float2 p = in.position.xy / max(u.frame.z, 1e-3);
    if (u.ripple.w > 0.5) { p = rippleSource(p, u.ripple.xy, u.ripple.z, 6.0, 56.0, 480.0); }
    px.position = p;
    px.palette = palette(u.stops, u.counts.x);
    return px;
}

/// Fill, reveal and dither: the passes SwiftUI applies around the stitchable functions.
static inline half4 ambientFinish(half4 color, AmbientPixel px, constant AmbientUniforms &u) {
    float2 p = px.pixel / max(u.frame.z, 1e-3);
    float m = fillMask(p.y / px.size.y, u.params.w) * revealMask(p, u.reveal);
    return dither(color * half(m), px.pixel, u.halo.w);
}

} // namespace cranny
