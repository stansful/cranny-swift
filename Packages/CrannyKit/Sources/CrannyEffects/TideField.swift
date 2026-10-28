// CrannyEffects/TideField.swift — luminous wave lines along the bottom edge (DESIGN.md §5.3, §5.6 `tideField`).
// Shader: Tide.metal (`tideField` stitchable, `tideFragment` for the Metal layer). Fallback: the Canvas below,
// three tapered ribbons with a 3-pt bloom drawn from `TideMath`, the Swift twin of `cranny::tide`.
import CrannyCore
import Foundation
import SwiftUI

/// Three soft wave lines of palette light near the bottom edge (line i in stop i); they thin and fade toward
/// both ends. Louder audio raises the waves (3 → 10 pt). Alpha is clamped to `Glow.ambientAlphaCap(level)`.
/// - Rendering: a dedicated Metal layer whenever shaders run, which `ImageRenderer`, `cacheDisplay`,
///   `drawingGroup()` and shader effects over the light cannot see; `ambientLightRendering(.inline)` keeps it in SwiftUI.
public struct TideField: View, Animatable {
    /// The light's colours: line i takes stop i; a change cross-fades when animated. With Appearance ▸ Quality ▸
    /// Efficient (the theme's `ambientDetail`) the live light cross-fades a new palette by itself: set it without
    /// animation there, or every frame of a SwiftUI animation recolours its Core Animation layers (DESIGN.md §5.7).
    public var palette: AmbientPalette
    /// Settings ▸ Appearance ▸ Ambient light.
    public var level: AmbienceLevel
    /// 0…1: the wave amplitude grows from 3 to 10 pt.
    public var energy: Double
    /// Frame rate, pause and path: DESIGN.md §4.7.
    public var budget: EffectBudget
    /// The frame Reduce Motion freezes on.
    public var restingTime: Double = 7.3

    /// Tide lines in `palette` at `level`, timed by `budget`.
    public init(palette: AmbientPalette, level: AmbienceLevel, energy: Double, budget: EffectBudget) {
        self.palette = palette; self.level = level; self.energy = energy; self.budget = budget
    }

    /// Palette and energy, so a track change cross-fades the light.
    public nonisolated var animatableData: AnimatablePair<AmbientPalette.Vector, Double> {
        get { .init(palette.vector, energy) }
        set { palette.vector = newValue.first; energy = newValue.second }
    }

    public var body: some View {
        AmbientFieldView(effect: .tide, palette: palette, level: level, energy: energy, fill: 1, budget: budget,
                         restingTime: restingTime)
    }
}

// MARK: - Math (twin of cranny::tide in Tide.metal)

nonisolated enum TideMath {
    static let lineCount = 3

    struct Line: Equatable {
        var base: Double          // pt from the top
        var amplitude: Double     // pt
        var k: Double             // rad per pt
        var omega: Double         // rad per s
        var phase: Double
    }

    /// Line `i` (0…2) on a field of `size` points: baseline 80 / 86 / 92 % of the height, amplitude
    /// (3 + 7 · energy) · (1 − 0.2 · i) pt, spatial and temporal rates of the Canvas design (DESIGN.md §5.6).
    static func line(_ i: Int, size: CGSize, energy: Double) -> Line {
        let fi = Double(i), width = max(Double(size.width), 1)
        return Line(base: Double(size.height) * (0.80 + 0.06 * fi),
                    amplitude: (3 + 7 * energy) * (1 - 0.2 * fi),
                    k: 2 * .pi * (0.75 + 0.35 * fi) / width,
                    omega: 2 * .pi * (0.09 + 0.035 * fi),
                    phase: 2.1 * fi)
    }

    /// y(x) = base + A · [sin(kx + ωt + φ) + 0.45 · sin(1.9kx − 1.4ωt)], and its slope.
    static func y(_ line: Line, x: Double, time: Double) -> (y: Double, slope: Double) {
        let a1 = line.k * x + line.omega * time + line.phase
        let a2 = 1.9 * line.k * x - 1.4 * line.omega * time
        return (line.base + line.amplitude * (sin(a1) + 0.45 * sin(a2)),
                line.amplitude * line.k * (cos(a1) + 0.855 * cos(a2)))
    }

    /// sin(π · u)^0.6: the lines thin and fade toward both ends.
    static func taper(_ u: Double) -> Double { pow(max(sin(.pi * min(max(u, 0), 1)), 0), 0.6) }

    /// cap · (0.55 + 0.45 · intensity).
    static func strength(_ level: AmbienceLevel) -> Double {
        Glow.ambientAlphaCap(level) * (0.55 + 0.45 * level.intensity)
    }
}

// MARK: - SwiftUI fallback

/// Three ribbons (the soft core, ≈ 1.75 pt × taper) over a blurred 6-pt bloom, each filled with a horizontal
/// gradient that follows the taper.
struct TideFallback: View {
    var glows: [RGB]
    var level: AmbienceLevel
    var energy: Double
    var time: Double

    var body: some View {
        let glows = glows, level = level, energy = energy, time = time
        Canvas(opaque: false, rendersAsynchronously: true) { ctx, size in
            guard !glows.isEmpty, size.width >= 1 else { return }
            // Everything is drawn at alpha / cap into one layer composited at opacity cap: crossing lines and the
            // core over its bloom can never pass the cap (the shader sums, then clamps).
            let k = TideMath.strength(level) / max(Glow.ambientAlphaCap(level), 0.001)
            ctx.opacity = Glow.ambientAlphaCap(level)
            ctx.drawLayer { layer in
                for i in 0..<TideMath.lineCount {
                    let line = TideMath.line(i, size: size, energy: energy)
                    let color = glows[i % glows.count]
                    // Normalized alpha along the line: the bloom b = 0.35 · k · τ, and the core c over it so that
                    // c + b · (1 − c) equals the shader's clamped centre, min(1, 1.35 · k · τ).
                    let shading = { (alpha: (Double) -> Double) -> GraphicsContext.Shading in
                        let stops = (0...10).map { j in
                            let u = Double(j) / 10
                            return Gradient.Stop(color: color.color(alpha(TideMath.taper(u))), location: u)
                        }
                        return .linearGradient(Gradient(stops: stops), startPoint: .zero,
                                               endPoint: CGPoint(x: size.width, y: 0))
                    }
                    let bloom = { (taper: Double) in 0.35 * k * taper }
                    let core = { (taper: Double) -> Double in
                        let b = bloom(taper), total = min(1, 1.35 * k * taper)
                        return b < 1 ? max(0, (total - b) / (1 - b)) : 0
                    }
                    layer.drawLayer { glow in                         // 0.35 · exp(−(d/3)²): a 6-pt band, blurred
                        glow.addFilter(.blur(radius: 2.5))
                        glow.fill(Self.ribbon(line, size: size, time: time, halfWidth: { _ in 3 }), with: shading(bloom))
                    }
                    // 1 − smoothstep(0.5τ, 1.25τ, d) ≈ a band of half-width 0.875τ.
                    layer.fill(Self.ribbon(line, size: size, time: time, halfWidth: { 0.875 * TideMath.taper($0) }),
                               with: shading(core))
                }
            }
        }
    }

    /// The band between y(x) − w and y(x) + w (w measured across the line), sampled every 2 pt.
    private nonisolated static func ribbon(_ line: TideMath.Line, size: CGSize, time: Double,
                                           halfWidth: (Double) -> Double) -> Path {
        let width = Double(size.width)
        let xs = Array(stride(from: 0.0, through: width, by: 2)) + [width]
        var top: [CGPoint] = [], bottom: [CGPoint] = []
        for x in xs {
            let (y, slope) = TideMath.y(line, x: x, time: time)
            let w = halfWidth(x / width) * (1 + slope * slope).squareRoot()
            top.append(CGPoint(x: x, y: y - w))
            bottom.append(CGPoint(x: x, y: y + w))
        }
        var path = Path()
        path.addLines(top + bottom.reversed())
        path.closeSubpath()
        return path
    }
}

// MARK: - Previews

#Preview("Tide · subtle") {
    TideField(palette: .afterglow, level: .subtle, energy: 0.2, budget: .previewRunning)
        .frame(width: 656, height: 170)
        .background(.black)
        .crannyThemeRoot(CrannyTheme())
}

#Preview("Tide · vivid, fallback") {
    TideFallback(glows: AmbientPalette.timer.glows, level: .vivid, energy: 0.6, time: 4)
        .frame(width: 656, height: 170)
        .background(.black)
        .crannyThemeRoot(CrannyTheme())
}
