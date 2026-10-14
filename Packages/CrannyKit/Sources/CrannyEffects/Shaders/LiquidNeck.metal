// CrannyEffects/Shaders/LiquidNeck.metal — Satellite split (DESIGN.md §4.3, §5.6 `liquidNeck`): a liquid union of the
// two black bodies (the shape's trailing end and the satellite bubble) for the first 0.38 s.
// Fallback: Canvas blur + alphaThreshold (LiquidNeck.swift). Surface, not light: opaque black, no cap.
#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
#include "CrannyShaders.h"
using namespace metal;

namespace cranny {

/// Points from `p` along `direction` to the first place where the layer is solid (alpha ≥ 0.5), or INFINITY when
/// there is none within `limit`. Marches in `step`s, then bisects the last step three times and interpolates the
/// alpha ramp, so the distance is continuous to well under a pixel.
static inline float neckHit(SwiftUI::Layer layer, float2 p, float2 direction, float limit, float step) {
    float t0 = 0.0, a0 = float(layer.sample(p).a);
    if (a0 >= 0.5) { return 0.0; }
    for (float t1 = step; t1 < limit + step; t1 += step) {
        float a1 = float(layer.sample(p + direction * t1).a);
        if (a1 >= 0.5) {
            for (int i = 0; i < 3; i++) {
                float tm = 0.5 * (t0 + t1), am = float(layer.sample(p + direction * tm).a);
                if (am >= 0.5) { t1 = tm; a1 = am; } else { t0 = tm; a0 = am; }
            }
            float t = t0 + (0.5 - a0) / max(a1 - a0, 1e-3) * (t1 - t0);
            return t <= limit ? t : INFINITY;
        }
        t0 = t1; a0 = a1;
    }
    return INFINITY;
}

/// Whether `p` belongs to the neck: some line through it meets solid surface on BOTH sides, `span` points apart or
/// closer (12 directions, 15° apart). Properties the tests rely on:
///  * a lone convex body never swells (no line through an outside point meets it on both sides);
///  * no islands: every point of the neck lies on a segment of neck points that joins the two sides;
///  * the neck is concave (the chords lengthen away from the closest approach) and vanishes when the gap
///    passes `span`, so it thins and snaps as `span` shrinks.
static inline bool neckBridges(SwiftUI::Layer layer, float2 p, float span) {
    const int directions = 12;
    const float step = 1.5;
    for (int k = 0; k < directions; k++) {
        float angle = (float(k) + 0.5) * M_PI_F / float(directions);
        float2 d = float2(cos(angle), sin(angle));
        float a = neckHit(layer, p, d, span, step);
        if (isinf(a)) { continue; }
        if (!isinf(neckHit(layer, p, -d, span - a, step))) { return true; }
    }
    return false;
}

} // namespace cranny

/// `.layerEffect` over both bodies, `maxSampleOffset` = 2 · reach + 1 pt. The bodies merge across gaps up to
/// 2 · reach (the neck's `span`); reach shrinks to 0 over the last 30 % of the split, so the neck thins and snaps.
/// The edge is anti-aliased with four rotated-grid samples per pixel (sized for 2× displays).
/// Swift: `.float(reach), .float(progress), .color(.black)`.
[[ stitchable ]] half4 liquidNeck(float2 position, SwiftUI::Layer layer, float reach, float progress, half4 fill) {
    half4 here = layer.sample(position);
    float r = reach * (1.0 - smoothstep(0.7, 1.0, clamp(progress, 0.0, 1.0)));     // gone at the end of the split
    if (r < 0.25 || here.a >= 0.999h) { return fill * here.a; }
    const float2 samples[4] = { float2(-0.0625, -0.1875), float2(0.1875, -0.0625),
                                float2(0.0625, 0.1875), float2(-0.1875, 0.0625) };
    float coverage = 0.0;
    for (int i = 0; i < 4; i++) {
        if (cranny::neckBridges(layer, position + samples[i], 2.0 * r)) { coverage += 0.25; }
    }
    return fill * half(max(float(here.a), coverage));    // the bodies keep their own anti-aliased outline
}
