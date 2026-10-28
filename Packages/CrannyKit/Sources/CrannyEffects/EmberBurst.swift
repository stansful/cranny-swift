// CrannyEffects/EmberBurst.swift — Timer done (DESIGN.md §5.5, §5.6 `emberBurst`): 18 stateless embers fan out of
// the notch for 0.9 s. Shader: Ember.metal. Fallback: the same embers in a Canvas (`EmberMath` is the Swift twin of
// `cranny::emberPosition`). Reduce Motion and Appearance ▸ Quality ▸ Efficient: a static ember glow that fades in
// and out.
import CrannyCore
import Foundation
import SwiftUI

/// The timer-done burst. Frame it at `EmberBurst.size`, centred under the shape's bottom edge: the embers start at
/// the view's top centre (under the camera) and fall outward and down. Remove it after `onFinished`.
public struct EmberBurst: View {
    /// The burst's frame: 280 × 140 pt.
    public static let size = CGSize(width: 280, height: 140)
    /// Seconds from trigger to the last ember going out.
    public static let duration = 0.9

    /// The embers' colours (`.timer`: ember → amber → rose).
    public var palette: AmbientPalette
    /// Settings ▸ Appearance ▸ Ambient light; moments show at least at Subtle strength even when the light is Off.
    public var level: AmbienceLevel
    /// Frame rate (AC / battery) and path (Reduce Motion, Low Power).
    public var budget: EffectBudget
    /// Called once when the burst is over.
    public var onFinished: (() -> Void)?

    /// Appearance ▸ Quality: Efficient plays the still variant (no Metal, no Canvas, DESIGN.md §5.7).
    @Environment(\.cranny.ambientDetail) private var detail

    /// An ember burst in `palette` (default `.timer`).
    public init(palette: AmbientPalette = .timer, level: AmbienceLevel, budget: EffectBudget,
                onFinished: (() -> Void)? = nil) {
        self.palette = palette; self.level = level; self.budget = budget; self.onFinished = onFinished
    }

    public var body: some View {
        let cap = Glow.ambientAlphaCap(max(level, .subtle))
        let origin = CGPoint(x: Self.size.width / 2, y: 0)
        Group {
            switch MomentPath.resolve(budget: budget, detail: detail, shadersAvailable: ShaderEffects.isAvailable) {
            case .reduced:
                ReducedMoment(duration: Self.duration, onFinished: onFinished) {
                    HaloFallback(glow: palette.glow1, level: max(level, .subtle),
                                 placement: HaloPlacement(center: .top, radius: 56))
                }
            case .shader:
                MomentClock(duration: Self.duration, interval: EffectTiming.momentInterval(budget),
                            onFinished: onFinished) { t in
                    Rectangle().colorEffect(ShaderEffects.library.emberBurst(
                        .boundingRect, .float2(origin), .float(t), .colorArray(palette.glows.map { $0.color(1) }),
                        .float(cap)))
                }
            case .fallback:
                MomentClock(duration: Self.duration, interval: EffectTiming.momentInterval(budget),
                            onFinished: onFinished) { t in
                    EmberCanvas(glows: palette.glows, cap: cap, origin: origin, time: t)
                }
            }
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Math (twin of Ember.metal)

nonisolated enum EmberMath {
    static let count = 18

    /// Ember `i`'s position `t` seconds after the burst (120–260 pt/s, drag, 60 pt/s² of gravity).
    static func position(_ i: Int, origin: CGPoint, time t: Double) -> CGPoint {
        let n = UInt32(i)
        let angle = (-75 + 150 * StatelessHash.hash(n + 18)) * .pi / 180
        let speed = 120 + 140 * StatelessHash.hash(n + 36)
        let travel = speed * (1 - exp(-2.6 * t)) / 2.6
        return CGPoint(x: origin.x + sin(angle) * travel, y: origin.y + cos(angle) * travel + 30 * t * t)
    }

    static func life(_ i: Int) -> Double { 0.55 + 0.35 * StatelessHash.hash(UInt32(i) + 72) }
    static func radius(_ i: Int) -> Double { 1.2 + 1.4 * StatelessHash.hash(UInt32(i) + 54) }
    static func stop(_ i: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return Int(StatelessHash.hash(UInt32(i) + 90) * Double(count)) % count
    }

    /// Fade (1 − t/life)² times flicker 0.75 + 0.25 · sin(19t + seed); 0 once the ember is out.
    static func brightness(_ i: Int, time t: Double) -> Double {
        let life = life(i)
        guard t < life else { return 0 }
        let fade = (1 - t / life) * (1 - t / life)
        return fade * (0.75 + 0.25 * sin(19 * t + 2 * .pi * StatelessHash.hash(UInt32(i))))
    }
}

// MARK: - SwiftUI fallback

/// The 18 embers as capsules (the 0.05-s trail) with a soft skirt, drawn at alpha / cap in one layer at opacity cap.
struct EmberCanvas: View {
    var glows: [RGB]
    var cap: Double
    var origin: CGPoint
    var time: Double

    var body: some View {
        let glows = glows, cap = cap, origin = origin, time = time
        Canvas(opaque: false, rendersAsynchronously: true) { ctx, _ in
            guard !glows.isEmpty else { return }
            ctx.opacity = cap
            ctx.drawLayer { layer in
                for i in 0..<EmberMath.count {
                    let brightness = EmberMath.brightness(i, time: time)
                    guard brightness > 0 else { continue }
                    let head = EmberMath.position(i, origin: origin, time: time)
                    let tail = EmberMath.position(i, origin: origin, time: max(time - 0.05, 0))
                    let r = EmberMath.radius(i)
                    let color = glows[EmberMath.stop(i, count: glows.count)]
                    var trail = Path()
                    trail.move(to: tail)
                    trail.addLine(to: head)
                    // Skirt 0.4 · exp(−(d/3r)²): a wide, blurred stroke; core exp(−(d/r)²): a narrow one.
                    layer.drawLayer { glow in
                        glow.addFilter(.blur(radius: 2 * r))
                        glow.stroke(trail, with: .color(color.color(min(1, 0.4 * brightness))),
                                    style: StrokeStyle(lineWidth: 4 * r, lineCap: .round))
                    }
                    layer.stroke(trail, with: .color(color.color(min(1, brightness))),
                                 style: StrokeStyle(lineWidth: 1.4 * r, lineCap: .round))
                }
            }
        }
    }
}

// MARK: - Previews

#Preview("Ember burst") {
    EmberBurst(level: .subtle, budget: .previewRunning)
        .background(.black)
        .crannyThemeRoot(CrannyTheme())
}

#Preview("Ember burst · fallback at 0.3 s") {
    EmberCanvas(glows: AmbientPalette.timer.glows, cap: 0.8, origin: CGPoint(x: 140, y: 0), time: 0.3)
        .frame(width: EmberBurst.size.width, height: EmberBurst.size.height)
        .background(.black)
        .crannyThemeRoot(CrannyTheme())
}

#Preview("Ember burst · Reduce Motion") {
    EmberBurst(level: .vivid, budget: .previewReduceMotion)
        .background(.black)
        .crannyThemeRoot(CrannyTheme())
}
