// CrannyEffects/Shaders/LiquidNeck.metal — Satellite split (DESIGN.md §4.3, §5.6 `liquidNeck`): a liquid union of the
// two black bodies (the shape's trailing end and the satellite bubble) for the first 0.38 s.
// Fallback: Canvas blur + alphaThreshold (LiquidNeck.swift). Surface, not light: opaque black, no cap.
#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
#include "CrannyShaders.h"
using namespace metal;

/// `.layerEffect` with `maxSampleOffset` = reach. 13 taps of the layer's alpha: the centre, 6 at reach/2, 6 at reach.
///  * The Gaussian-weighted mean of the taps keeps each body's own outline (it is 0.5 on a straight edge).
///  * The bridge, the largest min(alpha) over the 6 pairs of opposite taps, is 1 only for a point that has a body on
///    both sides within the reach: bodies closer than about 2 · reach merge with a concave neck that thins as they
///    part, and a lone body never swells.
/// alpha = smoothstep(0.42, 0.58, max(mean, (bridge + mean) / 2)). Swift: `.float(reach), .float(progress), .color(.black)`.
[[ stitchable ]] half4 liquidNeck(float2 position, SwiftUI::Layer layer, float reach, float progress, half4 fill) {
    float r = reach * (1.0 - smoothstep(0.7, 1.0, clamp(progress, 0.0, 1.0)));    // gone at the end of the split
    float field = float(layer.sample(position).a);
    if (r >= 0.25) {
        const float inner = 0.60653066;                                          // exp(−0.5): taps at reach/2 (σ = reach/2)
        const float outer = 0.13533528;                                          // exp(−2):   taps at reach
        float sum = field, norm = 1.0 + 6.0 * (inner + outer), bridge = 0.0;
        for (int k = 0; k < 3; k++) {                                            // opposite pairs: k and k + 3
            float a = float(k) * M_PI_F / 3.0;
            float2 d1 = float2(cos(a), sin(a)) * (0.5 * r);
            float2 d2 = float2(cos(a + M_PI_F / 6.0), sin(a + M_PI_F / 6.0)) * r;
            float n1 = float(layer.sample(position + d1).a), n2 = float(layer.sample(position - d1).a);
            float f1 = float(layer.sample(position + d2).a), f2 = float(layer.sample(position - d2).a);
            sum += inner * (n1 + n2) + outer * (f1 + f2);
            bridge = max(bridge, max(min(n1, n2), min(f1, f2)));
        }
        float mean = sum / norm;
        field = max(mean, 0.5 * (bridge + mean));          // the mean smooths the bridge's six facets
    }
    return fill * half(smoothstep(0.42, 0.58, field));
}
