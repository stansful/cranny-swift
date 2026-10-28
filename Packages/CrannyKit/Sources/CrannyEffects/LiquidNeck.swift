// CrannyEffects/LiquidNeck.swift — Satellite split (DESIGN.md §4.3, §5.5, §5.6 `liquidNeck`): while a second activity
// buds off the trailing edge, the two black bodies join with a concave liquid neck that thins and snaps within
// 0.38 s. Shader: LiquidNeck.metal (a chord union in a `.layerEffect`). Fallback: Canvas blur + alphaThreshold.
// Calm, Instant, Reduce Motion and Appearance ▸ Quality ▸ Efficient: no neck (the satellite simply fades in; the
// caller animates that).
import CrannyCore
import SwiftUI

/// Draws `content` (the trailing end of the shape and the satellite bubble, both black, clipped by the caller to the
/// strip between them) as one liquid surface. Drive `progress` from 0 to 1 with the satellite spring (0.38 s).
/// Surface, not light: opaque black, no alpha cap. Both paths merge the bodies across gaps up to 2 · reach and let go
/// at the same progress (± 0.03); neither ever swells a body or leaves a fragment between them.
public struct LiquidNeck<Content: View>: View, Animatable {
    /// 0…1 over the satellite spring; the neck's reach shrinks to 0 over the last 30 %, so it snaps by the end.
    public var progress: Double
    /// Points: bodies closer than twice this merge.
    public var reach: CGFloat
    /// Path only (Reduce Motion, Low Power, shader availability); the neck never needs a clock of its own.
    public var budget: EffectBudget
    private let content: Content

    @Environment(\.cranny) private var theme

    /// The neck between the bodies in `content`.
    public init(progress: Double, reach: CGFloat = 7, budget: EffectBudget, @ViewBuilder content: () -> Content) {
        self.progress = progress; self.reach = reach; self.budget = budget; self.content = content()
    }

    /// `progress`, so the caller's spring drives the neck frame by frame.
    public nonisolated var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    public var body: some View {
        let path = MomentPath.resolve(budget: budget, detail: theme.ambientDetail, shadersAvailable: ShaderEffects.isAvailable)
        if path == .reduced || theme.reduceMotion || theme.motion == .calm || theme.motion == .instant {
            content
        } else if path == .shader {
            content
                .compositingGroup()                               // one layer: the shader must see both bodies
                .layerEffect(ShaderEffects.library.liquidNeck(.float(reach), .float(progress), .color(.black)),
                             maxSampleOffset: NeckMath.maxSampleOffset(reach))
                .accessibilityHidden(true)
        } else {
            let reach = NeckMath.reach(reach, progress: progress)
            Canvas(opaque: false, rendersAsynchronously: false) { ctx, _ in
                guard let bodies = ctx.resolveSymbol(id: NeckMath.symbol) else { return }
                if reach >= NeckMath.minimumReach {
                    // The classic metaball: blur, keep the dense part as solid black, soften that edge by a hair
                    // (filters apply last-added first). The blur is tuned so the bodies let go at the shader's
                    // progress. It erodes convex ends, so the bodies are drawn again on top, untouched; the threshold
                    // sits a little above 0.5 so that straight edges stay just inside the bodies (no swelling).
                    var neck = ctx
                    neck.addFilter(.blur(radius: NeckMath.edgeSoftening))
                    neck.addFilter(.alphaThreshold(min: NeckMath.fallbackThreshold, color: .black))
                    neck.addFilter(.blur(radius: reach * NeckMath.fallbackBlur))
                    neck.drawLayer { layer in layer.draw(bodies, at: .zero, anchor: .topLeading) }
                }
                ctx.draw(bodies, at: .zero, anchor: .topLeading)
            } symbols: {
                content.tag(NeckMath.symbol)
            }
            .accessibilityHidden(true)
        }
    }
}

// MARK: - Math (twin of LiquidNeck.metal)

nonisolated enum NeckMath {
    static let symbol = 0
    /// Below this reach (points) neither path draws a neck (the shader returns the layer as it is).
    static let minimumReach: CGFloat = 0.25
    /// The Canvas blur radius per point of reach. A Gaussian metaball merges facing edges across ≈ 1.35 σ (less for
    /// round ends); this factor makes the fallback let go at the shader's progress (± 0.01 for round, square and
    /// straight ends; the tests allow ± 0.03).
    static let fallbackBlur: CGFloat = 1.6
    /// The Canvas threshold: a blurred straight edge reads 0.5 exactly on the edge, so 0.55 keeps it ≈ 0.13 σ inside.
    static let fallbackThreshold = 0.55
    /// The fallback's anti-aliasing of the thresholded edge (points).
    static let edgeSoftening: CGFloat = 0.3

    /// The neck's reach at `progress`: full until 70 %, then down to 0 (smoothstep), so the neck snaps.
    static func reach(_ reach: CGFloat, progress: Double) -> CGFloat {
        reach * (1 - Easing.smoothstep(0.7, 1, progress))
    }

    /// How far the shader samples: chords up to 2 · reach, plus its sub-pixel samples.
    static func maxSampleOffset(_ reach: CGFloat) -> CGSize {
        CGSize(width: 2 * reach + 1, height: 2 * reach + 1)
    }
}

// MARK: - Previews

private struct NeckPreview: View {
    var progress: Double
    var budget: EffectBudget = .previewRunning
    var body: some View {
        LiquidNeck(progress: progress, budget: budget) {
            ZStack(alignment: .leading) {
                Capsule().fill(.black).frame(width: 120, height: 32)
                Circle().fill(.black).frame(width: 32, height: 32).offset(x: 112 + 14 * progress)
            }
            .frame(width: 180, height: 48)
        }
        .frame(width: 180, height: 48)
        .background(CrannyTheme().palette.cardHover)
    }
}

#Preview("Liquid neck · joined, thinning, snapped") {
    VStack(spacing: Space.m) {
        NeckPreview(progress: 0.5)
        NeckPreview(progress: 0.85)
        NeckPreview(progress: 0.95)
    }
    .padding(Space.l)
    .crannyThemeRoot(CrannyTheme())
}

#Preview("Liquid neck · Canvas fallback") {
    VStack(spacing: Space.m) {
        NeckPreview(progress: 0.5, budget: .previewLowPower)
        NeckPreview(progress: 0.85, budget: .previewLowPower)
        NeckPreview(progress: 0.95, budget: .previewLowPower)
    }
    .padding(Space.l)
    .crannyThemeRoot(CrannyTheme())
}
