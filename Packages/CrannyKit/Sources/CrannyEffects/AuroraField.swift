// CrannyEffects/AuroraField.swift — DESIGN.md Appendix B (signature effect), plus the Metal path:
// while motion is allowed the aurora is drawn by `Shaders/Aurora.metal` (`ShaderAurora`); the SwiftUI
// path below (MeshGradient on 15+, Canvas on 14) stays for Reduce Motion (a frozen resting frame), Low
// Power (static halo) and Macs where the shader library cannot load.
import SwiftUI
import CrannyCore

// MARK: - Aurora (signature effect)

/// Curtains of content colour rising from the bottom edge of the open Nook. The top 40 % stays
/// black so the band merges with the hardware. Alpha is clamped to `Glow.ambientAlphaCap`.
public struct AuroraField: View, Animatable {
    public var palette: AmbientPalette
    public var level: AmbienceLevel
    public var energy: Double            // 0…1 (real RMS with permission, else 0)
    public var budget: EffectBudget
    public var restingTime: Double = 7.3

    public init(palette: AmbientPalette, level: AmbienceLevel, energy: Double, budget: EffectBudget) {
        self.palette = palette; self.level = level; self.energy = energy; self.budget = budget
    }

    public nonisolated var animatableData: AnimatablePair<AmbientPalette.Vector, Double> {
        get { .init(palette.vector, energy) }
        set { palette.vector = newValue.first; energy = newValue.second }
    }

    public var body: some View {
        let interval = budget.minimumInterval
        TimelineView(.animation(minimumInterval: interval ?? 1, paused: interval == nil)) { tl in
            let t = interval == nil ? restingTime : tl.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3600)
            Group {
                if budget.effective(.aurora) == .halo {
                    RadialGradient(colors: [palette.glow1.color(cap * 0.6), .clear], center: .bottom, startRadius: 0, endRadius: 260)
                } else if usesShader {
                    ShaderAurora(palette: palette, cap: cap, energy: energy, time: t)
                } else if #available(macOS 15.0, *) {
                    mesh(t)
                } else {
                    curtains(t)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var cap: Double { Glow.ambientAlphaCap(level) }

    /// Metal whenever motion is allowed. While paused (closed, occluded, full screen) the shader keeps
    /// drawing its resting frame, so closing never swaps renderers mid-animation.
    private var usesShader: Bool { !budget.reduceMotion && !budget.lowPower && EffectShaders.isAvailable }

    @available(macOS 15.0, *)
    private func mesh(_ time: Double) -> some View {
        let t = Float(time), e = Float(energy)
        func drift(_ i: Int, _ amp: Float) -> Float { amp * sin(t * (0.21 + 0.05 * Float(i)) + Float(i) * 1.7) }
        let swell = 0.08 + 0.06 * e
        let points: [SIMD2<Float>] = [
            [0, 0], [0.33, 0], [0.67, 0], [1, 0],
            [0, 0.42], [0.33 + drift(1, 0.05), 0.40 + drift(2, 0.03)], [0.67 + drift(3, 0.05), 0.42 + drift(4, 0.03)], [1, 0.42],
            [0, 0.72 - swell], [0.30 + drift(5, 0.08), 0.70 - swell + drift(6, 0.06)],
            [0.70 + drift(7, 0.08), 0.68 - swell + drift(8, 0.06)], [1, 0.74 - swell],
            [0, 1], [0.33 + drift(9, 0.04), 1], [0.67 + drift(10, 0.04), 1], [1, 1],
        ]
        let a = cap * (0.8 + 0.2 * energy)
        let g = palette.glows, clear = Color.black.opacity(0)
        let colors: [Color] = [
            clear, clear, clear, clear,
            clear, g[1].color(a * 0.10), g[2].color(a * 0.10), clear,
            g[0].color(a * 0.35), g[1].color(a * 0.55), g[2].color(a * 0.50), g[0].color(a * 0.30),
            g[2].color(a * 0.70), g[0].color(a * 1.00), g[1].color(a * 0.90), g[2].color(a * 0.65),
        ]
        return MeshGradient(width: 4, height: 4, points: points, colors: colors,
                            background: .clear, smoothsColors: true, colorSpace: .perceptual)
    }

    /// macOS 14: three blurred sine curtains, normal blending (keeps the audited alpha cap).
    private func curtains(_ time: Double) -> some View {
        let palette = palette, cap = cap, energy = energy
        return Canvas(opaque: false, colorMode: .linear, rendersAsynchronously: true) { ctx, size in
            ctx.addFilter(.blur(radius: max(10, size.height * 0.10)))
            let w = Double(size.width), hgt = Double(size.height)
            for (i, c) in palette.glows.enumerated() {
                let fi = Double(i)
                let phase = time * (0.09 + 0.035 * fi) * 2 * .pi
                let base = hgt * (0.62 + 0.10 * fi)
                let amp = hgt * (0.09 + 0.06 * energy) * (1 - 0.2 * fi)
                var path = Path()
                path.move(to: CGPoint(x: -40, y: hgt + 40))
                var x = -40.0
                while x <= w + 40 {
                    let u = x / max(w, 1)
                    path.addLine(to: CGPoint(x: x, y: base + amp * sin(u * 2 * .pi * (0.75 + 0.35 * fi) + phase)
                                                   + amp * 0.45 * sin(u * 2 * .pi * (1.9 + 0.2 * fi) - phase * 1.4)))
                    x += 10
                }
                path.addLine(to: CGPoint(x: w + 40, y: hgt + 40)); path.closeSubpath()
                let a = cap * 0.6 * (0.8 + 0.2 * energy)
                let grad = Gradient(stops: [.init(color: c.color(0), location: 0), .init(color: c.color(a), location: 0.35),
                                            .init(color: c.color(a * 0.25), location: 0.75), .init(color: c.color(0), location: 1)])
                ctx.fill(path, with: .linearGradient(grad, startPoint: CGPoint(x: 0, y: base - amp * 1.6), endPoint: CGPoint(x: 0, y: hgt)))
            }
        }
    }
}

#Preview("Aurora · subtle") {
    AuroraField(palette: .afterglow, level: .subtle, energy: 0.3,
                budget: EffectBudget(isOpen: true, onScreen: true, lowPower: false, fullScreenFront: false,
                                     reduceMotion: false, onBattery: false))
        .frame(width: 656, height: 170)
        .background(.black)
        .crannyThemeRoot(CrannyTheme())
}
