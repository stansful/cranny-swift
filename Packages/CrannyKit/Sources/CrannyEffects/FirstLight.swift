// CrannyEffects/FirstLight.swift — the first open per session (DESIGN.md §5.5, §5.6 "First light"): the ambient light
// fills outward from the camera over 1.0 s, with a soft crest of glow1 riding out from it. The reveal reaches the
// light through the environment, so it works on every ambient path (the Metal layer gets it as a uniform, the
// SwiftUI paths as a radial mask). Reduce Motion: a static fade.
import CrannyCore
import Foundation
import SwiftUI

/// Wraps the ambient light (an `AmbientLayer` or a field) and reveals it from the camera outward, once. Remove the
/// wrapper after `onFinished`, or keep it: once the light has landed it draws only `content` (no crest, no mask).
public struct FirstLight<Content: View>: View {
    /// Seconds from the open to the fully revealed light.
    public static var duration: Double { FirstLightMath.duration }

    /// The light's colours (`glow1` rides the front as a crest).
    public var palette: AmbientPalette
    /// Settings ▸ Appearance ▸ Ambient light; the crest shows at least at Subtle strength.
    public var level: AmbienceLevel
    /// Frame rate (AC / battery) and path (Reduce Motion, Low Power).
    public var budget: EffectBudget
    /// Called once when the light is fully revealed.
    public var onFinished: (() -> Void)?
    private let content: Content

    @State private var size: CGSize = .zero

    /// Reveals `content` (the ambient light) outward from the top centre.
    public init(palette: AmbientPalette, level: AmbienceLevel, budget: EffectBudget, onFinished: (() -> Void)? = nil,
                @ViewBuilder content: () -> Content) {
        self.palette = palette; self.level = level; self.budget = budget; self.onFinished = onFinished
        self.content = content()
    }

    public var body: some View {
        Group {
            switch MomentPath.resolve(budget: budget, shadersAvailable: ShaderEffects.isAvailable) {
            case .reduced:
                ReducedReveal(duration: Self.duration, onFinished: onFinished) { content }
            case .shader, .fallback:
                MomentClock(duration: Self.duration, interval: EffectTiming.momentInterval(budget),
                            onFinished: onFinished) { t in
                    // One structure throughout, so the light inside keeps its identity (and its fill) when it lands;
                    // once landed there is no reveal and the crest draws nothing.
                    let reveal = FirstLightMath.reveal(elapsed: t, size: size)
                    content
                        .environment(\.ambientReveal, t < Self.duration ? reveal : nil)
                        .overlay {
                            FirstLightCrest(palette: palette, level: level, budget: budget, reveal: reveal, elapsed: t)
                        }
                }
            }
        }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
    }
}

/// The crest: a haloGlow in glow1 at 0.5 · cap that grows with the reveal and fades as it lands (no pop on removal).
/// Like the light it rides, it keeps the band (the top 40 %) black; the shader crest is dithered (DESIGN.md §5.6
/// rule 5). Once the light has landed it draws nothing at all.
struct FirstLightCrest: View {
    var palette: AmbientPalette
    var level: AmbienceLevel
    var budget: EffectBudget
    var reveal: AmbientReveal
    var elapsed: Double

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        if elapsed < FirstLightMath.duration {
            glow
                .mask { BandMask() }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder private var glow: some View {
        let fade = 1 - Easing.easeInOut(elapsed / FirstLightMath.duration)
        let cap = Glow.ambientAlphaCap(max(level, .subtle)) * 0.5 * fade
        let placement = HaloPlacement(center: .top, radius: max(reveal.radius * 0.6, 1))
        if ShaderEffects.usesShader(budget) {
            Rectangle()
                .colorEffect(ShaderEffects.library.haloGlow(.boundingRect, .float2(0.5, 0), .float(placement.radius),
                                                            .color(palette.glow1.color(1)), .float(cap)))
                .crannyDithered(scale: displayScale)
        } else {
            RadialGradient(gradient: HaloFallback.gradient(glow: palette.glow1, cap: cap), center: .top,
                           startRadius: 0, endRadius: placement.radius * 1.5)
        }
    }
}

// MARK: - Math

nonisolated enum FirstLightMath {
    /// Seconds from the open to the fully revealed light (DESIGN.md §5.5).
    static let duration = 1.0

    /// The reveal at `elapsed` seconds: the radius grows from the band's edge (40 % of the height, where the light
    /// begins) to 1.6 × the diagonal over 1.0 s (ease in and out, so the light visibly spreads for the whole second)
    /// with a soft edge of 35 % of the radius; the fully lit inside has passed the far corners when it lands (no pop).
    static func reveal(elapsed: Double, size: CGSize) -> AmbientReveal {
        let diagonal = (size.width * size.width + size.height * size.height).squareRoot()
        let start = 0.4 * size.height, end = 1.6 * diagonal
        let radius = start + Easing.easeInOut(elapsed / 1.0) * (end - start)
        return AmbientReveal(center: .top, radius: radius, feather: radius * 0.35)
    }
}

/// Reduce Motion: the light simply fades in (`ambientIn`, a 0.2-s dissolve under Reduce Motion), no radial movement.
private struct ReducedReveal<Content: View>: View {
    let duration: Double
    let onFinished: (() -> Void)?
    @ViewBuilder let content: () -> Content
    @Environment(\.cranny) private var theme
    @State private var isShown = false

    var body: some View {
        content()
            .opacity(isShown ? 1 : 0)
            .task {
                withAnimation(theme.animation(.ambientIn)) { isShown = true }
                do { try await Task.sleep(for: .seconds(duration)) } catch { return }
                onFinished?()
            }
    }
}

// MARK: - Previews

#Preview("First light") {
    FirstLight(palette: .afterglow, level: .subtle, budget: .previewRunning) {
        AmbientLayer(palette: .afterglow, level: .subtle, effect: .aurora, energy: 0, budget: .previewRunning)
    }
    .frame(width: 656, height: 170)
    .background(.black)
    .crannyThemeRoot(CrannyTheme())
}
