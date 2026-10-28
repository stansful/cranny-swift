// CrannyEffects/MotesField.swift — slow rising specks that twinkle (DESIGN.md §5.3, §5.6 `motesField`).
// Shader: Motes.metal (`motesField` stitchable, `motesFragment` for the Metal layer). Fallback: the Canvas below,
// drawing the same 36 stateless motes from `MoteMath`, the Swift twin of `cranny::mote`.
import CrannyCore
import Foundation
import SwiftUI

/// Thirty-six slow, twinkling specks of palette light rising from the bottom edge; they fade out before the top
/// 40 %, so the band stays black. Alpha is clamped to `Glow.ambientAlphaCap(level)` on every path.
/// - Rendering: a dedicated Metal layer whenever shaders run, which `ImageRenderer`, `cacheDisplay`,
///   `drawingGroup()` and shader effects over the light cannot see; `ambientLightRendering(.inline)` keeps it in SwiftUI.
public struct MotesField: View, Animatable {
    /// The light's colours: mote n takes stop n mod 3; a change cross-fades when animated. With Appearance ▸ Quality ▸
    /// Efficient (the theme's `ambientDetail`) the live light cross-fades a new palette by itself: set it without
    /// animation there, or every frame of a SwiftUI animation recolours its Core Animation layers (DESIGN.md §5.7).
    public var palette: AmbientPalette
    /// Settings ▸ Appearance ▸ Ambient light.
    public var level: AmbienceLevel
    /// 0…1: louder audio lifts the motes a little.
    public var energy: Double
    /// Frame rate, pause and path: DESIGN.md §4.7.
    public var budget: EffectBudget
    /// The frame Reduce Motion freezes on.
    public var restingTime: Double = 7.3

    /// Motes in `palette` at `level`, timed by `budget`.
    public init(palette: AmbientPalette, level: AmbienceLevel, energy: Double, budget: EffectBudget) {
        self.palette = palette; self.level = level; self.energy = energy; self.budget = budget
    }

    /// Palette and energy, so a track change cross-fades the light.
    public nonisolated var animatableData: AnimatablePair<AmbientPalette.Vector, Double> {
        get { .init(palette.vector, energy) }
        set { palette.vector = newValue.first; energy = newValue.second }
    }

    public var body: some View {
        AmbientFieldView(effect: .motes, palette: palette, level: level, energy: energy, fill: 1, budget: budget,
                         restingTime: restingTime)
    }
}

// MARK: - Math (twin of cranny::mote in Motes.metal)

nonisolated enum MoteMath {
    static let columns = 12
    static let perColumn = 3
    static let count = columns * perColumn
    /// Motes wrap this far below the bottom edge and above the top, so they never pop in view.
    static let margin = 8.0

    struct Mote: Equatable {
        var center: CGPoint
        var radius: Double
        var twinkle: Double
        /// Palette stop index before `mod count` (`cranny::stop`).
        var stop: Int
    }

    /// Mote `row` of `column` at `time` on a field of `size` points.
    static func mote(column: Int, row: Int, size: CGSize, time: Double, energy: Double) -> Mote {
        let n = UInt32(column * perColumn + row)
        let h0 = StatelessHash.hash(n), h1 = StatelessHash.hash(n + 36), h2 = StatelessHash.hash(n + 72)
        let h3 = StatelessHash.hash(n + 108), h4 = StatelessHash.hash(n + 144), h5 = StatelessHash.hash(n + 180)
        let width = max(Double(size.width), 1), height = max(Double(size.height), 1)
        let columnWidth = width / Double(columns)
        let speed = 5 + 9 * h2                                                // 5–14 pt/s
        let span = height + 2 * margin
        let travel = speed * time + 0.6 * energy * speed                      // louder audio lifts them
        let x = (Double(column) + 0.5 + (h0 - 0.5) * 0.6) * columnWidth + 4 * sin(0.6 * time + 2 * .pi * h1)
        let y = height + margin - (h3 * span + travel).truncatingRemainder(dividingBy: span)
        let frequency = 1.2 + 2 * h5                                          // 1.2–3.2 Hz
        let twinkle = 1 - 0.45 * (0.5 + 0.5 * sin(2 * .pi * frequency * time + 2 * .pi * h0))
        return Mote(center: CGPoint(x: x, y: y), radius: 0.8 + 1.6 * h4, twinkle: twinkle,
                    stop: Int(n))
    }

    /// Core plus a soft skirt: exp(−(d/r)²) + 0.25 · exp(−(d/3r)²).
    static func profile(distance d: Double, radius r: Double) -> Double {
        let x = d / r, y = d / (3 * r)
        return exp(-x * x) + 0.25 * exp(-y * y)
    }

    /// The light's ceiling scale: cap · (0.6 + 0.4 · intensity).
    static func strength(_ level: AmbienceLevel) -> Double {
        Glow.ambientAlphaCap(level) * (0.6 + 0.4 * level.intensity)
    }

    /// Fade to nothing in the top 40 % (smoothstep 0.40 → 0.60 of the height).
    static func fade(_ v: Double) -> Double { Easing.smoothstep(0.40, 0.60, v) }
}

// MARK: - SwiftUI fallback

/// The same 36 motes, each a radial gradient sampled from the shader's profile, masked by the top fade.
struct MotesFallback: View {
    var glows: [RGB]
    var level: AmbienceLevel
    var energy: Double
    var time: Double

    var body: some View {
        let glows = glows, level = level, energy = energy, time = time
        Canvas(opaque: false, rendersAsynchronously: true) { ctx, size in
            // Drawn at alpha / cap into one layer composited at opacity cap, so overlapping motes never pass it.
            let cap = Glow.ambientAlphaCap(level)
            let k = MoteMath.strength(level) / max(cap, 0.001)
            ctx.opacity = cap
            ctx.drawLayer { layer in
                for column in 0..<MoteMath.columns {
                    for row in 0..<MoteMath.perColumn {
                        let mote = MoteMath.mote(column: column, row: row, size: size, time: time, energy: energy)
                        let reach = 6.6 * mote.radius                             // the skirt is < 0.2 % beyond this
                        guard mote.center.y + reach > 0.40 * size.height, mote.center.y - reach < size.height,
                              !glows.isEmpty else { continue }
                        let color = glows[mote.stop % glows.count]
                        let stops = [0, 0.5, 1, 1.5, 2, 3, 4.5, 6.6].map { d in
                            Gradient.Stop(color: color.color(min(1, k * mote.twinkle *
                                                                 MoteMath.profile(distance: d * mote.radius, radius: mote.radius))),
                                          location: d / 6.6)
                        }
                        let rect = CGRect(x: mote.center.x - reach, y: mote.center.y - reach, width: 2 * reach, height: 2 * reach)
                        layer.fill(Path(ellipseIn: rect), with: .radialGradient(Gradient(stops: stops), center: mote.center,
                                                                                startRadius: 0, endRadius: reach))
                    }
                }
            }
        }
        .mask {
            LinearGradient(stops: (0...4).map { i in
                               let x = Double(i) / 4
                               return Gradient.Stop(color: .white.opacity(Easing.easeInOut(x)), location: 0.40 + 0.20 * x)
                           },
                           startPoint: .top, endPoint: .bottom)
        }
    }
}

// MARK: - Previews

#Preview("Motes · subtle") {
    MotesField(palette: .afterglow, level: .subtle, energy: 0, budget: .previewRunning)
        .frame(width: 656, height: 170)
        .background(.black)
        .crannyThemeRoot(CrannyTheme())
}

#Preview("Motes · vivid, fallback") {
    MotesFallback(glows: AmbientPalette.charging.glows, level: .vivid, energy: 0.4, time: 12)
        .frame(width: 656, height: 170)
        .background(.black)
        .crannyThemeRoot(CrannyTheme())
}
