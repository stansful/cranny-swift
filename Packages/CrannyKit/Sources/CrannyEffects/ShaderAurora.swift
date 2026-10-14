// CrannyEffects/ShaderAurora.swift — the Metal path of `AuroraField` (macOS 14+ stitchable colour effect).
// Same contract as the SwiftUI path: a pure function of time, palette, energy and the alpha cap.
import CrannyCore
import SwiftUI

/// Draws `Shaders/Aurora.metal` over its whole frame. Only `AuroraField` decides when to use it
/// (motion allowed, not Low Power, `EffectShaders.isAvailable`); it never ticks on its own.
struct ShaderAurora: View {
    var palette: AmbientPalette
    /// `Glow.ambientAlphaCap(level)`: the shader never exceeds it.
    var cap: Double
    var energy: Double
    var time: Double

    var body: some View {
        GeometryReader { proxy in
            Rectangle()
                .fill(Color.white)
                .colorEffect(EffectShaders.aurora(size: proxy.size, time: time, energy: energy, cap: cap, palette: palette))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

#Preview("Shader aurora · afterglow") {
    ShaderAurora(palette: .afterglow, cap: Glow.ambientAlphaCap(.vivid), energy: 0.4, time: 12)
        .frame(width: 656, height: 170)
        .background(.black)
        .crannyThemeRoot(CrannyTheme())
}
