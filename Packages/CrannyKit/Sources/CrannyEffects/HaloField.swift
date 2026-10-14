// CrannyEffects/HaloField.swift — one static bloom (DESIGN.md §5.3, §5.6 `haloGlow`).
// Shader: Halo.metal (`haloGlow` stitchable, `haloFragment` for the Metal layer). Fallback: a RadialGradient whose
// stops sample the shader's Gaussian. The automatic Low Power / thermal halo is always that fallback.
import CrannyCore
import SwiftUI

/// A soft Gaussian bloom of `glow1`: alpha 0.6 · cap at `center`, fading to nothing past `radius`.
public struct HaloField: View, Animatable {
    /// The light's colours (`glow1` blooms).
    public var palette: AmbientPalette
    /// Settings ▸ Appearance ▸ Ambient light.
    public var level: AmbienceLevel
    /// Path only: the halo is static, so it never needs frames.
    public var budget: EffectBudget
    /// Unit point in the view (default: the bottom edge's centre).
    public var center: UnitPoint
    /// Points; alpha falls to 3.6 % of its peak at this distance.
    public var radius: CGFloat

    /// A halo of `palette.glow1` at `level`.
    public init(palette: AmbientPalette, level: AmbienceLevel, budget: EffectBudget,
                center: UnitPoint = .bottom, radius: CGFloat = 260) {
        self.palette = palette; self.level = level; self.budget = budget; self.center = center; self.radius = radius
    }

    /// Palette and radius, so colour changes cross-fade and the bloom can grow.
    public nonisolated var animatableData: AnimatablePair<AmbientPalette.Vector, CGFloat> {
        get { .init(palette.vector, radius) }
        set { palette.vector = newValue.first; radius = newValue.second }
    }

    public var body: some View {
        var still = budget
        still.isOpen = false                                  // a static bloom needs no clock
        return AmbientFieldView(effect: .halo, palette: palette, level: level, energy: 0, fill: 1, budget: still,
                                restingTime: 0, halo: HaloPlacement(center: center, radius: radius))
    }
}

// MARK: - SwiftUI fallback

/// The halo as a RadialGradient: the Gaussian 0.6 · cap · exp(−2.8 · (d/R)²) sampled at 11 stops out to 1.5 R,
/// where it is below 0.2 % (no crease where a two-stop gradient would end).
struct HaloFallback: View {
    var glow: RGB
    var level: AmbienceLevel
    var placement: HaloPlacement

    var body: some View {
        RadialGradient(gradient: Self.gradient(glow: glow, cap: Glow.ambientAlphaCap(level)),
                       center: placement.center, startRadius: 0, endRadius: placement.radius * 1.5)
    }

    static func gradient(glow: RGB, cap: Double) -> Gradient {
        Gradient(stops: (0...10).map { i in
            let x = Double(i) / 10 * 1.5                       // distance in units of R
            return .init(color: glow.color(0.6 * cap * exp(-2.8 * x * x)), location: Double(i) / 10)
        })
    }
}

// MARK: - Previews

#Preview("Halo · subtle") {
    HaloField(palette: .afterglow, level: .subtle, budget: .previewRunning)
        .frame(width: 656, height: 170)
        .background(.black)
        .crannyThemeRoot(CrannyTheme())
}

#Preview("Halo · Low Power fallback") {
    HaloField(palette: .charging, level: .vivid, budget: .previewLowPower)
        .frame(width: 656, height: 170)
        .background(.black)
        .crannyThemeRoot(CrannyTheme())
}
