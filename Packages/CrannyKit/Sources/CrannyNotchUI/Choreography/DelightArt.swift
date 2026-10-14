// CrannyNotchUI/Choreography/DelightArt.swift — how the one-shot moments look (DESIGN.md §5.5, App. B):
// the ember burst under the shape, the first-light mask of the light layer and the charge sweep's light
// profile. These are the SwiftUI designs of §5.5 (the "fallback specification" of §5.6), drawn here until
// WP11's `EmberBurst`, `FirstLight` and `ChargeSweep` (CrannyEffects, Metal + fallback) land; then each view
// below becomes a call to its CrannyEffects counterpart and the maths moves with it.
import CrannyCore
import SwiftUI

// MARK: - Ember burst (timer done)

/// 18 stateless embers fanning out of the shape's bottom edge for 0.9 s. Time comes from `EffectClock` at the
/// budget's rate and only for the moment's lifetime; Reduce Motion shows a static ember glow that fades.
struct EmberBurstView: View {
    @Environment(\.cranny) private var theme
    let playback: DelightPlayback
    /// `DelightPlayback.frameInterval`: 1/30 s on AC, 1/20 s on battery, nil (paused) while not visible.
    let frameInterval: Double?

    static let size = CGSize(width: 280, height: 140)

    var body: some View {
        let palette = AmbientPalette.timer
        let cap = Glow.ambientAlphaCap(max(theme.effectiveAmbience, .subtle))
        Group {
            if theme.reduceMotion {
                RadialGradient(colors: [palette.glow1.color(cap * 0.6), .clear], center: .top, startRadius: 0, endRadius: 90)
                    .modifier(FadeOut(duration: playback.lifetime))
            } else {
                EffectClock(minimumInterval: frameInterval) { date in
                    let t = playback.elapsed(at: date)
                    Canvas(opaque: false, rendersAsynchronously: true) { context, size in
                        EmberField.draw(in: &context, size: size, time: t, stops: palette.glows, cap: cap)
                    }
                }
            }
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The ember maths (pure): positions are functions of time and seed only.
nonisolated enum EmberField {
    static let count = 18

    struct Ember: Equatable {
        var position: CGPoint
        var direction: CGVector                    // unit vector of the current velocity
        var radius: CGFloat
        var alpha: Double
        var stop: Int
    }

    /// Hash of an integer to 0..<1 (deterministic, platform-independent).
    static func hash(_ n: Int, _ salt: UInt64) -> Double {
        var x = UInt64(truncatingIfNeeded: n) &* 0x9E37_79B9_7F4A_7C15 &+ salt
        x ^= x >> 30; x = x &* 0xBF58_476D_1CE4_E5B9
        x ^= x >> 27; x = x &* 0x94D0_49BB_1331_11EB
        x ^= x >> 31
        return Double(x >> 11) / Double(UInt64(1) << 53)
    }

    /// Ember `i` at `t` seconds, from an origin at the top centre of `size`; nil once its life is over.
    static func ember(_ i: Int, time t: Double, size: CGSize, stopCount: Int) -> Ember? {
        let life = 0.55 + 0.35 * hash(i, 1)
        guard t >= 0, t < life else { return nil }
        let angle = (-75 + 150 * hash(i, 2)) * .pi / 180          // ±75° around straight down
        let speed = 70 + 90 * hash(i, 3)
        let travel = speed * (1 - exp(-3 * t)) / 3                  // drag
        let gravity = 0.5 * 22 * t * t
        let dx = sin(angle), dy = cos(angle)
        let x = Double(size.width) / 2 + dx * travel
        let y = dy * travel + gravity
        let vx = dx * speed * exp(-3 * t), vy = dy * speed * exp(-3 * t) + 22 * t
        let norm = max(hypot(vx, vy), 0.001)
        let fade = pow(1 - t / life, 2)
        let flicker = 0.75 + 0.25 * sin(19 * t + 6.28 * hash(i, 4))
        return Ember(position: CGPoint(x: x, y: y), direction: CGVector(dx: vx / norm, dy: vy / norm),
                     radius: 1.2 + 1.4 * hash(i, 5), alpha: fade * flicker,
                     stop: Int(hash(i, 6) * Double(max(stopCount, 1))) % max(stopCount, 1))
    }

    static func draw(in context: inout GraphicsContext, size: CGSize, time: Double, stops: [RGB], cap: Double) {
        context.blendMode = .plusLighter
        for i in 0..<count {
            guard let e = ember(i, time: time, size: size, stopCount: stops.count) else { continue }
            let colour = stops.isEmpty ? RGB.white : stops[e.stop]
            // A capsule along the velocity: the 0.05-s trail.
            let trail = CGFloat(0.05 * 60) * e.radius
            var path = Path()
            path.move(to: e.position)
            path.addLine(to: CGPoint(x: e.position.x - e.direction.dx * trail, y: e.position.y - e.direction.dy * trail))
            let alpha = min(e.alpha * cap, cap)
            context.stroke(path, with: .color(colour.color(alpha * 0.4)),
                           style: StrokeStyle(lineWidth: e.radius * 3, lineCap: .round))
            context.stroke(path, with: .color(colour.color(alpha)),
                           style: StrokeStyle(lineWidth: e.radius * 2, lineCap: .round))
        }
    }
}

/// Fades its content from 1 to 0 over `duration` once (Reduce Motion variants: no movement, colour only).
private struct FadeOut: ViewModifier {
    let duration: Double
    @State private var visible = true
    func body(content: Content) -> some View {
        content.opacity(visible ? 1 : 0)
            .onAppear { withAnimation(.easeIn(duration: duration)) { visible = false } }
    }
}

// MARK: - First light (first open per session)

/// Mask of the light layer: light fills outward from the camera (top centre) over 1.0 s, with a brighter crest
/// riding the front. `progress` is animated 0 → 1 by the caller; Reduce Motion uses a plain fade instead.
struct FirstLightMask: View, Animatable {
    var progress: Double
    nonisolated var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        GeometryReader { proxy in
            let diagonal = hypot(proxy.size.width, proxy.size.height)
            let radius = max(diagonal * 1.4 * progress, 1)
            RadialGradient(stops: [.init(color: .white, location: 0), .init(color: .white, location: 0.72),
                                   .init(color: .clear, location: 1)],
                           center: .top, startRadius: 0, endRadius: radius)
        }
    }
}

/// The crest of first light: a soft ring of `glow1` at half the cap riding the mask's front.
struct FirstLightCrest: View, Animatable {
    var progress: Double
    let glow: RGB
    let cap: Double
    nonisolated var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        GeometryReader { proxy in
            let diagonal = hypot(proxy.size.width, proxy.size.height)
            let radius = max(diagonal * 1.4 * progress, 1)
            RadialGradient(stops: [.init(color: .clear, location: 0), .init(color: .clear, location: 0.6),
                                   .init(color: glow.color(cap * 0.5 * (1 - progress)), location: 0.82),
                                   .init(color: .clear, location: 1)],
                           center: .top, startRadius: 0, endRadius: radius)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Charge sweep (charger connected)

/// Light of the sweep along the lower rim at `u` (0 = leading end, 1 = trailing end) and `progress` 0…1
/// (DESIGN.md §5.6 `chargeSweep`: a head plus a fading tail; pure, unit-tested).
nonisolated enum ChargeSweepProfile {
    static func head(progress: Double) -> Double {
        let p = min(max(progress, 0), 1)
        let eased = p < 0.5 ? 2 * p * p : 1 - pow(-2 * p + 2, 2) / 2      // easeInOut
        return eased * 1.2 - 0.1
    }

    static func light(at u: Double, progress: Double) -> Double {
        let s = head(progress: progress)
        let core = exp(-pow((u - s) / 0.05, 2))
        let tail = u <= s ? 0.45 * smoothstep(s - 0.30, s, u) : 0
        return min(core + tail, 1)
    }

    static func smoothstep(_ a: Double, _ b: Double, _ x: Double) -> Double {
        let t = min(max((x - a) / (b - a), 0), 1)
        return t * t * (3 - 2 * t)
    }

    /// Gradient stops sampling `light` across the rim (used as the sweep's mask).
    static func stops(progress: Double, samples: Int = 24) -> [Gradient.Stop] {
        (0...samples).map { k in
            let u = Double(k) / Double(samples)
            return Gradient.Stop(color: .white.opacity(light(at: u, progress: progress)), location: u)
        }
    }
}

#Preview("Ember burst · 0.1 / 0.3 / 0.6 s") {
    HStack(spacing: Space.l) {
        ForEach([0.1, 0.3, 0.6], id: \.self) { t in
            Canvas { context, size in
                EmberField.draw(in: &context, size: size, time: t, stops: AmbientPalette.timer.glows, cap: 0.8)
            }
            .frame(width: EmberBurstView.size.width, height: EmberBurstView.size.height)
            .background(.black)
        }
    }
    .padding()
    .background(Color(white: 0.2))
}

#Preview("First light · 40 %") {
    AuroraPlaceholder()
        .mask { FirstLightMask(progress: 0.4) }
        .overlay { FirstLightCrest(progress: 0.4, glow: AmbientPalette.afterglow.glow1, cap: 0.45) }
        .frame(width: 656, height: 170)
        .background(.black)
}

/// A flat stand-in for the light layer in the first-light preview.
private struct AuroraPlaceholder: View {
    var body: some View {
        LinearGradient(colors: [.clear, BrandColor.iris.color(0.45), BrandColor.lagoon.color(0.45)],
                       startPoint: .top, endPoint: .bottom)
    }
}
