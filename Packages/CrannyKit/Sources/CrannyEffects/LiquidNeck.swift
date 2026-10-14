// CrannyEffects/LiquidNeck.swift — Satellite split (DESIGN.md §4.3, §5.5, §5.6 `liquidNeck`): while a second activity
// buds off the trailing edge, the two black bodies join with a concave liquid neck that thins and snaps within
// 0.38 s. Shader: LiquidNeck.metal (a metaball union in a `.layerEffect`). Fallback: Canvas blur + alphaThreshold.
// Calm, Instant and Reduce Motion: no neck (the satellite simply fades in; the caller animates that).
import CrannyCore
import SwiftUI

/// Draws `content` (the trailing end of the shape and the satellite bubble, both black, clipped by the caller to the
/// strip between them) as one liquid surface. Drive `progress` from 0 to 1 with the satellite spring (0.38 s).
/// Surface, not light: opaque black, no alpha cap.
public struct LiquidNeck<Content: View>: View, Animatable {
    /// 0…1 over the satellite spring; the neck's reach shrinks to 0 over the last 30 %, so it snaps by the end.
    public var progress: Double
    /// Points: bodies closer than about twice this merge (about 1.1 × on the Canvas fallback).
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
        let path = MomentPath.resolve(budget: budget, shadersAvailable: ShaderEffects.isAvailable)
        if path == .reduced || theme.reduceMotion || theme.motion == .calm || theme.motion == .instant {
            content
        } else if path == .shader {
            content
                .compositingGroup()                               // one layer: the shader must see both bodies
                .layerEffect(ShaderEffects.library.liquidNeck(.float(reach), .float(progress), .color(.black)),
                             maxSampleOffset: CGSize(width: reach, height: reach))
                .accessibilityHidden(true)
        } else {
            let radius = NeckMath.reach(reach, progress: progress) * 0.8      // gaps up to ≈ 1.1 · reach merge
            Canvas(opaque: false, rendersAsynchronously: false) { ctx, _ in
                // The classic metaball: blur, then keep alpha ≥ 0.5 as solid black (filters apply last-added first).
                ctx.addFilter(.alphaThreshold(min: 0.5, color: .black))
                ctx.addFilter(.blur(radius: radius))
                ctx.drawLayer { layer in
                    if let bodies = layer.resolveSymbol(id: NeckMath.symbol) { layer.draw(bodies, at: .zero, anchor: .topLeading) }
                }
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

    /// The neck's reach at `progress`: full until 70 %, then down to 0 (smoothstep), so the neck snaps.
    static func reach(_ reach: CGFloat, progress: Double) -> CGFloat {
        reach * (1 - Easing.smoothstep(0.7, 1, progress))
    }
}

// MARK: - Previews

private struct NeckPreview: View {
    var progress: Double
    var body: some View {
        LiquidNeck(progress: progress, budget: .previewRunning) {
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

#Preview("Liquid neck · 0, 0.5, 0.9") {
    VStack(spacing: Space.m) {
        NeckPreview(progress: 0)
        NeckPreview(progress: 0.5)
        NeckPreview(progress: 0.9)
    }
    .padding(Space.l)
    .crannyThemeRoot(CrannyTheme())
}
