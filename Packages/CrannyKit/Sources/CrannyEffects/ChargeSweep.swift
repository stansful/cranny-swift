// CrannyEffects/ChargeSweep.swift — Charger connected (DESIGN.md §5.1, §5.5, §5.6 `chargeSweep`): a green head with a
// fading tail runs once along the lower outline (the progress-rim path) in 0.8 s. Shader: ChargeSweep.metal on a
// 1.5-pt core over a 4-pt soft under-stroke. Fallback: a `trim` of the same path. Reduce Motion and Appearance ▸
// Quality ▸ Efficient: the rim at once.
import CrannyCore
import Foundation
import SwiftUI

/// A one-shot sweep of light along `outline`, the shape's lower outline in this view's coordinates (left to right,
/// x-monotonic, like the progress rim). Remove it after `onFinished`.
public struct ChargeSweep: View {
    /// Seconds from trigger to the end of the sweep.
    public static let duration = 0.8

    /// The lower outline, in this view's coordinate space.
    public var outline: Path
    /// `glow1` lights the sweep (`.charging`: the `success` green).
    public var palette: AmbientPalette
    /// Settings ▸ Appearance ▸ Ambient light; moments show at least at Subtle strength even when the light is Off.
    public var level: AmbienceLevel
    /// Frame rate (AC / battery) and path (Reduce Motion, Low Power).
    public var budget: EffectBudget
    /// Called once when the sweep is over.
    public var onFinished: (() -> Void)?

    /// Appearance ▸ Quality: Efficient plays the still variant (no Metal, no Canvas, DESIGN.md §5.7).
    @Environment(\.cranny.ambientDetail) private var detail

    /// A sweep along `outline` in `palette.glow1` (default `.charging`).
    public init(outline: Path, palette: AmbientPalette = .charging, level: AmbienceLevel, budget: EffectBudget,
                onFinished: (() -> Void)? = nil) {
        self.outline = outline; self.palette = palette; self.level = level; self.budget = budget
        self.onFinished = onFinished
    }

    public var body: some View {
        let cap = Glow.ambientAlphaCap(max(level, .subtle))
        let glow = palette.glow1
        Group {
            switch MomentPath.resolve(budget: budget, detail: detail, shadersAvailable: ShaderEffects.isAvailable) {
            case .reduced:
                ReducedMoment(duration: Self.duration, onFinished: onFinished) {
                    RimStrokes(outline: outline, color: glow.color(1))
                        .compositingGroup()
                        .opacity(cap)
                }
            case .shader:
                MomentClock(duration: Self.duration, interval: EffectTiming.momentInterval(budget),
                            onFinished: onFinished) { t in
                    SweepShader(outline: outline, glow: glow, cap: cap, progress: t / Self.duration)
                }
            case .fallback:
                MomentClock(duration: Self.duration, interval: EffectTiming.momentInterval(budget),
                            onFinished: onFinished) { t in
                    SweepTrim(outline: outline, glow: glow, cap: cap, progress: t / Self.duration)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Math (twin of ChargeSweep.metal)

nonisolated enum SweepMath {
    /// The head's position along the outline (0…1 of the width) at `progress`: easeInOut · 1.2 − 0.1, so it enters
    /// and leaves past the ends.
    static func head(_ progress: Double) -> Double { Easing.easeInOut(progress) * 1.2 - 0.1 }

    /// Light at `u` (0…1 along the outline): a Gaussian head plus a 0.30-long tail at 0.45, faded out at the end.
    static func light(at u: Double, progress: Double) -> Double {
        let s = head(progress)
        let x = (u - s) / 0.05
        let tail = u <= s ? 0.45 * Easing.smoothstep(s - 0.30, s, u) : 0
        return (exp(-x * x) + tail) * (1 - Easing.smoothstep(0.85, 1, progress))
    }
}

// MARK: - Views

/// The rim: a 4-pt soft under-stroke for bloom and a 1.5-pt core (DESIGN.md §5.6).
struct RimStrokes: View {
    var outline: Path
    var color: Color

    var body: some View {
        ZStack {
            outline.stroke(color.opacity(0.5), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .blur(radius: 1.5)
            outline.stroke(color, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
        }
    }
}

/// The shader path: `chargeSweep` over the rim's coverage. The outline's bounding box stands in for arc length.
struct SweepShader: View {
    var outline: Path
    var glow: RGB
    var cap: Double
    var progress: Double

    var body: some View {
        let bounds = outline.boundingRect
        RimStrokes(outline: outline, color: .white)
            .compositingGroup()                                     // one coverage mask, so the light is capped once
            .colorEffect(ShaderEffects.library.chargeSweep(
                .float4(bounds.minX, bounds.minY, bounds.width, bounds.height), .float(progress),
                .color(glow.color(1)), .float(cap)))
    }
}

/// The fallback: the tail (0.30 of the outline at 0.45) and the head (± 0.05) as trims of the rim, drawn at alpha / cap
/// and composited once at opacity cap, so the overlap never passes the cap.
struct SweepTrim: View {
    var outline: Path
    var glow: RGB
    var cap: Double
    var progress: Double

    var body: some View {
        let s = SweepMath.head(progress)
        let fade = 1 - Easing.smoothstep(0.85, 1, progress)
        ZStack {
            RimStrokes(outline: outline.trimmedPath(from: min(max(s - 0.30, 0), 1), to: min(max(s, 0), 1)),
                       color: glow.color(0.45 * fade))
            RimStrokes(outline: outline.trimmedPath(from: min(max(s - 0.05, 0), 1), to: min(max(s + 0.05, 0), 1)),
                       color: glow.color(fade))
        }
        .compositingGroup()
        .opacity(cap)
    }
}

// MARK: - Previews

private let previewOutline: Path = {
    var path = Path()
    path.move(to: CGPoint(x: 20, y: 10))
    path.addQuadCurve(to: CGPoint(x: 40, y: 30), control: CGPoint(x: 20, y: 30))
    path.addLine(to: CGPoint(x: 260, y: 30))
    path.addQuadCurve(to: CGPoint(x: 280, y: 10), control: CGPoint(x: 280, y: 30))
    return path
}()

#Preview("Charge sweep") {
    ChargeSweep(outline: previewOutline, level: .vivid, budget: .previewRunning)
        .frame(width: 300, height: 44)
        .background(.black)
        .crannyThemeRoot(CrannyTheme())
}

#Preview("Charge sweep · fallback at 45 %") {
    SweepTrim(outline: previewOutline, glow: AmbientPalette.charging.glow1, cap: 0.8, progress: 0.45)
        .frame(width: 300, height: 44)
        .background(.black)
        .crannyThemeRoot(CrannyTheme())
}
