// CrannyEffects/CoreAnimation/AmbientCAEffects.swift — the four ambient effects of Appearance ▸ Quality ▸ Efficient
// (DESIGN.md §5.7) as Core Animation layers: gradient and shape layers with looping animations that the window server
// runs. Nothing here draws on the CPU per frame, uses Metal or keeps a timer; each effect only builds its layers, lays
// them out for a size, colours them for a palette and level, and (re)installs its animations at a frame rate.
//
// Every effect keeps the light's promises (DESIGN.md §5.6 rules 4 and 7, §5.7):
// - Alpha cap: the effect's `group` composites its layers into one image (group opacity) drawn at
//   `Glow.ambientAlphaCap(level)`; inside it every colour has alpha ≤ 1, so overlapping light never passes the cap.
//   Channels are clamped to `Glow.maxBrightness`.
// - The band: aurora and motes lie under a mask that is clear over the top 40 % (as the SwiftUI fallbacks); the tide
//   lines sit at 80–92 % of the height.
// - Looping: every animation repeats forever from `AmbientCAClock.epoch` in the clock layer's time, with periods that
//   share no small common multiple, so the light never visibly loops; its values are fractions (anchor points, scales,
//   opacities) or fixed point offsets, so a resize changes the layers' geometry but never a looping animation.
// - Song change: the view lifts the whole light once (`AmbientCANSView`); the tide instead deepens its waves in place
//   (`playSwell`, path keyframes drawn for the current size, dropped by a resize).
// - Live audio energy is not used (it would need work per frame in the app); the light shows energy 0.
import AppKit
import CrannyCore
import QuartzCore
import SwiftUI

/// One ambient effect as Core Animation layers. The view (`AmbientCANSView`) owns the clock and the cross-fades.
protocol AmbientCAEffect: AnyObject {
    /// Composited at the alpha cap, with the effect's static mask. The view puts its swell and clock layers in it and
    /// `content` under them.
    var group: CALayer { get }
    /// The light's layers (the view adds it under its clock layer).
    var content: CALayer { get }
    /// Positions every layer for a light of `size` points (y down from the top edge).
    func layout(_ size: CGSize)
    /// Colours for `glows` at `level` (the cap is the group's opacity, which the view sets).
    func apply(glows: [RGB], level: AmbienceLevel)
    /// (Re)installs the looping animations, each asking for `frameRate` frames per second.
    func installAnimations(frameRate: Float)
    /// The layers that hold looping animations now (tests).
    var animatedLayers: [CALayer] { get }
    /// Plays the song-change swell itself, started `elapsed` seconds ago, asking for `frameRate`; false leaves it to
    /// the view, which lifts the whole light (the default).
    func playSwell(elapsed: Double, frameRate: Float) -> Bool
    /// Drops a swell that `playSwell` started (the clock is about to jump to another time).
    func stopSwell()
}

extension AmbientCAEffect {
    func playSwell(elapsed: Double, frameRate: Float) -> Bool { false }
    func stopSwell() {}
}

// MARK: - Shared helpers

nonisolated enum AmbientCA {
    /// An sRGB colour with every channel clamped to 0…`Glow.maxBrightness` and alpha to 0…1.
    static func color(_ rgb: RGB, _ alpha: Double) -> CGColor {
        func clamp(_ v: Double) -> CGFloat { CGFloat(min(max(v, 0), Glow.maxBrightness)) }
        return CGColor(srgbRed: clamp(rgb.r), green: clamp(rgb.g), blue: clamp(rgb.b),
                       alpha: CGFloat(min(max(alpha, 0), 1)))
    }

    /// Stop `i` of `glows` (modulo their count); black when there is none.
    static func stop(_ glows: [RGB], _ i: Int) -> RGB {
        glows.isEmpty ? .zero : glows[i % glows.count]
    }

    /// A layer that never animates on its own: no implicit actions for the properties the light sets.
    static func still<L: CALayer>(_ layer: L) -> L {
        layer.actions = ["position": NSNull(), "bounds": NSNull(), "frame": NSNull(), "opacity": NSNull(),
                         "colors": NSNull(), "locations": NSNull(), "path": NSNull(), "strokeColor": NSNull(),
                         "contents": NSNull(), "hidden": NSNull(), "mask": NSNull(), "sublayers": NSNull(),
                         "transform": NSNull(), "anchorPoint": NSNull(), "startPoint": NSNull(),
                         "endPoint": NSNull(), "lineWidth": NSNull(), "contentsScale": NSNull()]
        return layer
    }

    /// A vertical gradient mask in unit space (y down): `stops` are (location, alpha) pairs.
    static func verticalMask(_ stops: [(Double, Double)]) -> CAGradientLayer {
        let mask = still(CAGradientLayer())
        mask.colors = stops.map { CGColor(gray: 1, alpha: CGFloat($0.1)) }
        mask.locations = stops.map { NSNumber(value: $0.0) }
        mask.startPoint = CGPoint(x: 0.5, y: 0)
        mask.endPoint = CGPoint(x: 0.5, y: 1)
        return mask
    }

    /// A looping animation of `keyPath` from `from` to `to` and back (a sine-like breath), `period` seconds a cycle,
    /// starting `phase` (0…1 of the cycle) into it at the clock's epoch.
    static func breath(_ keyPath: String, from: Double, to: Double, period: Double, phase: Double,
                       frameRate: Float) -> CABasicAnimation {
        let animation = CABasicAnimation(keyPath: keyPath)
        animation.fromValue = from
        animation.toValue = to
        animation.duration = period / 2
        animation.autoreverses = true
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        return looping(animation, offset: phase * period, frameRate: frameRate)
    }

    /// A looping animation that runs from `from` to `to` at a constant speed, then starts again (`period` seconds).
    static func sweep(_ keyPath: String, from: Double, to: Double, period: Double, phase: Double,
                      frameRate: Float) -> CABasicAnimation {
        let animation = CABasicAnimation(keyPath: keyPath)
        animation.fromValue = from
        animation.toValue = to
        animation.duration = period
        animation.timingFunction = CAMediaTimingFunction(name: .linear)
        return looping(animation, offset: phase * period, frameRate: frameRate)
    }

    /// Repeats forever from `AmbientCAClock.epoch`, `offset` seconds into its cycle, asking for `frameRate`.
    static func looping<A: CAAnimation>(_ animation: A, offset: Double, frameRate: Float) -> A {
        animation.beginTime = AmbientCAClock.epoch
        animation.timeOffset = offset
        animation.repeatCount = .infinity
        animation.isRemovedOnCompletion = false
        animation.preferredFrameRateRange = CAFrameRateRange(minimum: max(frameRate / 2, 1), maximum: frameRate,
                                                             preferred: frameRate)
        return animation
    }

    /// The key of the song-change swell on any layer.
    static let swellKey = "songChange"

    /// The song-change swell of `keyPath` on `layer`: `values` at 0, 25, 60 and 100 % of the ripple's 0.6 s (quick
    /// rise, gentle settle), started `elapsed` seconds ago in the layer's own time. Starting it in the past (rather
    /// than with a `timeOffset`, which wraps around) plays only what is left of it.
    static func swell(_ keyPath: String, values: [Any], elapsed: Double, on layer: CALayer,
                      frameRate: Float) -> CAKeyframeAnimation {
        let swell = CAKeyframeAnimation(keyPath: keyPath)
        swell.values = values
        swell.keyTimes = [0, 0.25, 0.6, 1]
        swell.timingFunctions = [CAMediaTimingFunction(name: .easeOut), CAMediaTimingFunction(name: .easeInEaseOut),
                                 CAMediaTimingFunction(name: .easeIn)]
        swell.duration = Ripple.duration
        swell.beginTime = layer.convertTime(CACurrentMediaTime(), from: nil) - elapsed
        swell.preferredFrameRateRange = CAFrameRateRange(minimum: max(frameRate / 2, 1), maximum: frameRate,
                                                         preferred: frameRate)
        return swell
    }

    /// Radial-gradient colours of a curtain: alpha `peak` · (1 − smoothstep(0.3, 1, r)), full over the inner third and
    /// fading softly to the ellipse's edge (r 1), like the shader's envelope that is full from about 70 % of the height
    /// down and fades out toward the band.
    static func curtain(_ rgb: RGB, peak: Double) -> (colors: [CGColor], locations: [NSNumber]) {
        let radii = (0...10).map { Double($0) / 10 }
        let colors = radii.map { r in color(rgb, peak * (1 - Easing.smoothstep(0.3, 1, r))) }
        return (colors, radii.map { NSNumber(value: $0) })
    }

    /// A radial gradient layer that fills the ellipse inscribed in its bounds.
    static func ellipse() -> CAGradientLayer {
        let layer = still(CAGradientLayer())
        layer.type = .radial
        layer.startPoint = CGPoint(x: 0.5, y: 0.5)
        layer.endPoint = CGPoint(x: 1, y: 1)
        return layer
    }

    /// The group every effect draws into: group opacity (the alpha cap, set by the view) and `mask`.
    static func group(mask: CALayer?) -> CALayer {
        let group = still(CALayer())
        group.allowsGroupOpacity = true
        group.mask = mask
        return group
    }

    /// `StatelessHash` of `seed` (the Canvas fallbacks seed their particles the same way).
    static func hash(_ seed: Int) -> Double { StatelessHash.hash(UInt32(truncatingIfNeeded: seed)) }
}

// MARK: - Aurora

/// Curtains of palette light rising from the bottom edge to a flat, soft top: four wide glows along the edge (stops
/// 3 · 1 · 2 · 3 from left to right, as the fallback mesh's bottom row) and six thin streaks over them (1 · 2 · 3 ·
/// 1 · 2 · 3) with uneven tops. Each is the radial gradient of an ellipse centred on the bottom edge and only colours
/// the light: the group's static rise mask (clear over the top 40 %, then rising like the shader's light) makes the
/// top edge. Each curtain drifts sideways and breathes in height and brightness, each on its own period (12–45 s a
/// cycle).
final class AuroraCA: AmbientCAEffect {
    /// One curtain: where it stands (fractions of the light's size) and how it moves.
    nonisolated struct Curtain: Equatable, Sendable {
        var x: Double              // centre, fraction of the width
        var halfWidth: Double      // fraction of the width
        var halfHeight: Double     // fraction of the height (the curtain's top at rest: 1 − halfHeight)
        var stop: Int
        var isRay: Bool
        var drift: Double          // anchor-point travel, ± half this fraction of the curtain's own width
        var driftPeriod: Double
        var swell: ClosedRange<Double>   // height scale
        var swellPeriod: Double
        var glow: ClosedRange<Double>    // opacity
        var glowPeriod: Double
    }

    /// The curtains, back to front. The glows reach past the top edge, so they are nearly even over the lit 60 % and
    /// the rise mask alone shapes their top (no domes); the streaks are 5–7 % of the width wide and end between 15 %
    /// and 38 % from the top, under the mask. The glows drift ± 4 % of the width over 27–39 s, the streaks ± 3 % over
    /// 29–45 s.
    static let curtains: [Curtain] = [
        Curtain(x: 0.00, halfWidth: 0.34, halfHeight: 1.05, stop: 2, isRay: false, drift: 0.13, driftPeriod: 27.4,
                swell: 0.94...1.04, swellPeriod: 26.6, glow: 0.85...1, glowPeriod: 19.4),
        Curtain(x: 0.35, halfWidth: 0.30, halfHeight: 1.05, stop: 0, isRay: false, drift: 0.15, driftPeriod: 39.2,
                swell: 0.94...1.04, swellPeriod: 35.8, glow: 0.85...1, glowPeriod: 23.0),
        Curtain(x: 0.66, halfWidth: 0.30, halfHeight: 1.05, stop: 1, isRay: false, drift: 0.15, driftPeriod: 31.8,
                swell: 0.94...1.04, swellPeriod: 23.4, glow: 0.85...1, glowPeriod: 29.8),
        Curtain(x: 1.00, halfWidth: 0.34, halfHeight: 1.05, stop: 2, isRay: false, drift: 0.13, driftPeriod: 35.6,
                swell: 0.94...1.04, swellPeriod: 30.2, glow: 0.85...1, glowPeriod: 21.6),
        Curtain(x: 0.10, halfWidth: 0.030, halfHeight: 0.62, stop: 0, isRay: true, drift: 1.0, driftPeriod: 33.4,
                swell: 0.85...1.03, swellPeriod: 14.6, glow: 0.60...1, glowPeriod: 11.8),
        Curtain(x: 0.26, halfWidth: 0.025, halfHeight: 0.80, stop: 1, isRay: true, drift: 1.0, driftPeriod: 41.8,
                swell: 0.85...1.03, swellPeriod: 17.8, glow: 0.60...1, glowPeriod: 13.4),
        Curtain(x: 0.43, halfWidth: 0.035, halfHeight: 0.70, stop: 2, isRay: true, drift: 1.0, driftPeriod: 29.0,
                swell: 0.85...1.03, swellPeriod: 12.2, glow: 0.60...1, glowPeriod: 15.6),
        Curtain(x: 0.57, halfWidth: 0.028, halfHeight: 0.85, stop: 0, isRay: true, drift: 1.0, driftPeriod: 37.6,
                swell: 0.85...1.03, swellPeriod: 15.8, glow: 0.60...1, glowPeriod: 12.6),
        Curtain(x: 0.74, halfWidth: 0.032, halfHeight: 0.66, stop: 1, isRay: true, drift: 1.0, driftPeriod: 45.2,
                swell: 0.85...1.03, swellPeriod: 19.6, glow: 0.60...1, glowPeriod: 17.2),
        Curtain(x: 0.90, halfWidth: 0.026, halfHeight: 0.78, stop: 2, isRay: true, drift: 1.0, driftPeriod: 31.4,
                swell: 0.85...1.03, swellPeriod: 13.4, glow: 0.60...1, glowPeriod: 14.2),
    ]

    let group: CALayer
    let content = AmbientCA.still(CALayer())
    private let layers: [CAGradientLayer]

    init() {
        group = AmbientCA.group(mask: Self.riseMask())
        layers = Self.curtains.map { _ in AmbientCA.ellipse() }
        for layer in layers { content.addSublayer(layer) }
    }

    /// The aurora's static mask: clear over the top 40 %, then rising to opaque at 90 % of the height, fitted so that
    /// with the curtains under it each row's mean brightness follows the Metal aurora's (within ≈ 0.02 of alpha at
    /// Vivid, DESIGN.md §5.7): a flat, soft top whatever the curtains do.
    static let riseStops: [(location: Double, alpha: Double)] = [
        (0, 0), (0.40, 0), (0.45, 0.24), (0.50, 0.44), (0.55, 0.56), (0.60, 0.67), (0.65, 0.76), (0.70, 0.83),
        (0.80, 0.93), (0.90, 1), (1, 1),
    ]

    static func riseMask() -> CAGradientLayer {
        AmbientCA.verticalMask(riseStops.map { ($0.location, $0.alpha) })
    }

    /// Peak alpha (inside the group) of a curtain: the wide glows hold the edge, the streaks add structure, more of it
    /// at Vivid (DESIGN.md §5.6 rule 3: intensity scales structure, never the ceiling).
    static func peak(_ curtain: Curtain, level: AmbienceLevel) -> Double {
        curtain.isRay ? 0.20 + 0.15 * level.intensity : 0.66
    }

    /// Radial-gradient colours of a streak: alpha `peak` · (1 − smoothstep(0, 1, r)), no flat core, so it reads as a
    /// thin line of light rather than a column.
    static func streak(_ rgb: RGB, peak: Double) -> (colors: [CGColor], locations: [NSNumber]) {
        let radii = (0...10).map { Double($0) / 10 }
        let colors = radii.map { r in AmbientCA.color(rgb, peak * (1 - Easing.smoothstep(0, 1, r))) }
        return (colors, radii.map { NSNumber(value: $0) })
    }

    func layout(_ size: CGSize) {
        group.mask?.frame = CGRect(origin: .zero, size: size)
        for (layer, curtain) in zip(layers, Self.curtains) {
            layer.bounds = CGRect(x: 0, y: 0, width: 2 * curtain.halfWidth * size.width,
                                  height: 2 * curtain.halfHeight * size.height)
            layer.position = CGPoint(x: curtain.x * size.width, y: size.height)
        }
    }

    func apply(glows: [RGB], level: AmbienceLevel) {
        for (layer, curtain) in zip(layers, Self.curtains) {
            let rgb = AmbientCA.stop(glows, curtain.stop), peak = Self.peak(curtain, level: level)
            let bump = curtain.isRay ? Self.streak(rgb, peak: peak) : AmbientCA.curtain(rgb, peak: peak)
            layer.colors = bump.colors
            layer.locations = bump.locations
        }
    }

    func installAnimations(frameRate: Float) {
        // Drift, swell and glow phases come from separate hash ranges, so no two curtains share a phase.
        for (i, (layer, c)) in zip(layers, Self.curtains).enumerated() {
            layer.add(AmbientCA.breath("anchorPoint.x", from: 0.5 - c.drift / 2, to: 0.5 + c.drift / 2,
                                       period: c.driftPeriod, phase: AmbientCA.hash(i), frameRate: frameRate),
                      forKey: "drift")
            layer.add(AmbientCA.breath("transform.scale.y", from: c.swell.lowerBound, to: c.swell.upperBound,
                                       period: c.swellPeriod, phase: AmbientCA.hash(i + 40), frameRate: frameRate),
                      forKey: "swell")
            layer.add(AmbientCA.breath("opacity", from: c.glow.lowerBound, to: c.glow.upperBound,
                                       period: c.glowPeriod, phase: AmbientCA.hash(i + 80), frameRate: frameRate),
                      forKey: "glow")
        }
    }

    var animatedLayers: [CALayer] { layers.filter { !($0.animationKeys() ?? []).isEmpty } }
}

// MARK: - Motes

/// Thirty-six specks of palette light rising from below the bottom edge (12 columns × 3, seeded like `MoteMath`):
/// each rises at its own speed, sways ± 4 pt and twinkles, and fades out between 60 % and 40 % of the height under the
/// group's mask (clear above 40 %).
final class MotesCA: AmbientCAEffect {
    /// Points below the bottom edge where a mote starts and above the top where it ends, so none pops in view.
    static let margin: CGFloat = 20
    /// The open panel's light (DESIGN.md §6.1: 656 × 170), where the light is seen most: a mote's period is its speed
    /// over this span, so it rises at 5–14 pt/s there and proportionally faster or slower in a taller or shorter light
    /// (the animation stays a fraction of the height). Fixed rather than read from the bounds when the animations are
    /// installed: the light is built while the shape is still opening.
    static let referenceHeight: CGFloat = 170

    /// One mote's seeded parameters (`MoteMath.mote`'s hashes).
    nonisolated struct Mote: Equatable, Sendable {
        var column: Int
        var offset: Double        // fraction of a column from its centre, ±0.3
        var radius: Double        // pt, 0.8–2.4
        var speed: Double         // pt/s, 5–14
        var start: Double         // 0…1 of the rise at the light's time 0
        var sway: Double          // phase of the ± 4-pt sway, 0…1
        var twinkle: Double       // Hz, 1.2–3.2
        var twinklePhase: Double  // 0…1
        var stop: Int

        init(_ n: Int) {
            let h = (0..<6).map { AmbientCA.hash(n + 36 * $0) }
            column = n / MoteMath.perColumn
            offset = (h[0] - 0.5) * 0.6
            sway = h[1]
            speed = 5 + 9 * h[2]
            start = h[3]
            radius = 0.8 + 1.6 * h[4]
            twinkle = 1.2 + 2 * h[5]
            twinklePhase = h[0]
            stop = n
        }

        /// Pt from the centre to where the mote's skirt fades out (`MoteMath.profile` < 0.2 % beyond).
        var reach: Double { 6.6 * radius }
    }

    static let motes: [Mote] = (0..<MoteMath.count).map(Mote.init)

    let group: CALayer
    let content = AmbientCA.still(CALayer())
    /// One track per mote: a column-high layer whose anchor point carries the dot up the light.
    private let tracks: [CALayer]
    private let dots: [CAGradientLayer]

    init() {
        let fade = (0...4).map { i -> (Double, Double) in
            let x = Double(i) / 4
            return (0.40 + 0.20 * x, Easing.easeInOut(x))
        }
        group = AmbientCA.group(mask: AmbientCA.verticalMask([(0, 0)] + fade + [(1, 1)]))
        tracks = Self.motes.map { _ in AmbientCA.still(CALayer()) }
        dots = Self.motes.map { _ in AmbientCA.ellipse() }
        for (track, dot) in zip(tracks, dots) {
            track.anchorPoint = CGPoint(x: 0.5, y: 0)
            track.addSublayer(dot)
            content.addSublayer(track)
        }
    }

    func layout(_ size: CGSize) {
        group.mask?.frame = CGRect(origin: .zero, size: size)
        let columnWidth = size.width / CGFloat(MoteMath.columns)
        let span = size.height + 2 * Self.margin
        for (i, mote) in Self.motes.enumerated() {
            let reach = CGFloat(mote.reach)
            // The track spans the rise; its anchor point (animated 0 → 1) lifts it by its own height, so the dot at its
            // bottom edge goes from `margin` below the light to `margin` above it.
            tracks[i].bounds = CGRect(x: 0, y: 0, width: 2 * reach, height: span)
            tracks[i].position = CGPoint(x: (CGFloat(mote.column) + 0.5 + CGFloat(mote.offset)) * columnWidth,
                                         y: -Self.margin)
            dots[i].bounds = CGRect(x: 0, y: 0, width: 2 * reach, height: 2 * reach)
            dots[i].position = CGPoint(x: reach, y: span)
        }
    }

    /// Peak alpha (inside the group) of a mote's core: `MoteMath.strength` over the cap.
    static func strength(_ level: AmbienceLevel) -> Double { 0.6 + 0.4 * level.intensity }

    func apply(glows: [RGB], level: AmbienceLevel) {
        let strength = Self.strength(level)
        let distances = [0, 0.5, 1, 1.5, 2, 3, 4.5, 6.6]
        for (dot, mote) in zip(dots, Self.motes) {
            let rgb = AmbientCA.stop(glows, mote.stop)
            dot.colors = distances.map { d in
                AmbientCA.color(rgb, strength * MoteMath.profile(distance: d * mote.radius, radius: mote.radius))
            }
            dot.locations = distances.map { NSNumber(value: $0 / 6.6) }
        }
    }

    func installAnimations(frameRate: Float) {
        let span = Double(Self.referenceHeight + 2 * Self.margin)
        for (i, mote) in Self.motes.enumerated() {
            let period = span / mote.speed
            tracks[i].add(AmbientCA.sweep("anchorPoint.y", from: 0, to: 1, period: period, phase: mote.start,
                                          frameRate: frameRate), forKey: "rise")
            dots[i].add(AmbientCA.breath("transform.translation.x", from: -4, to: 4, period: 2 * .pi / 0.6,
                                         phase: mote.sway, frameRate: frameRate), forKey: "sway")
            dots[i].add(AmbientCA.breath("opacity", from: 1, to: 0.55, period: 1 / mote.twinkle,
                                         phase: mote.twinklePhase, frameRate: frameRate), forKey: "twinkle")
        }
    }

    var animatedLayers: [CALayer] {
        (tracks as [CALayer] + dots as [CALayer]).filter { !($0.animationKeys() ?? []).isEmpty }
    }
}

// MARK: - Tide

/// Three luminous wave lines along the bottom edge (line i in stop i, baseline at 80 / 86 / 92 % of the height): each
/// a path a light and a wavelength wide, stroked as a 1.75-pt core over four wider, fainter strokes that grade its
/// bloom (the shader's soft falloff), travelling one wavelength to the left per period (seamless: the path repeats
/// every wavelength). A horizontal mask thins the lines toward both ends, as the shader's taper. A song change deepens
/// the waves in place (`playSwell`). The lines are not rasterized: with five strokes a line, a cached bitmap per line
/// measured no cheaper in the window server (ARCHITECTURE.md §9.2).
final class TideCA: AmbientCAEffect {
    /// Line i's wavelength in widths of the light (`TideMath`'s spatial rate 0.75 + 0.35 i per width).
    static func cycles(_ i: Int) -> Double { 0.75 + 0.35 * Double(i) }
    /// Seconds per wavelength (`TideMath`'s temporal rate 0.09 + 0.035 i).
    static func period(_ i: Int) -> Double { 1 / (0.09 + 0.035 * Double(i)) }
    /// Amplitude at energy 0 (`TideMath.line`: (3 + 7 · energy) · (1 − 0.2 · i) pt).
    static func amplitude(_ i: Int) -> Double { 3 * (1 - 0.2 * Double(i)) }
    /// The strokes of one line, widest first: width (pt) and alpha relative to the line's strength (each capped at 1).
    /// Over black they sum to the shader's core plus its 0.35 · exp(−(d/3)²) bloom: the same peak, a graded edge.
    static let strokes: [(width: CGFloat, alpha: Double)] = [(9, 0.06), (7, 0.075), (5, 0.115), (3, 0.09), (1.75, 1.35)]
    /// Points above and below the line that its strokes and waves can reach, the song-change swell included.
    static let halfBand: CGFloat = 16
    /// The song-change swell: each line's amplitude over the ripple, in multiples of its resting amplitude (the
    /// shaders' energy pulse lifts the waves from 3 to 6.5 pt and lets them settle).
    static let swellScales: [Double] = [1, 2.1, 1.4, 1]

    let group: CALayer
    let content = AmbientCA.still(CALayer())
    /// One travelling layer per line, holding its strokes.
    private let lines: [CALayer]
    private let shapes: [[CAShapeLayer]]
    /// The light's size at the last layout (the swell's paths are drawn for it).
    private var size: CGSize = .zero

    init() {
        let taper = CAGradientLayer()
        taper.colors = (0...12).map { i in CGColor(gray: 1, alpha: CGFloat(TideMath.taper(Double(i) / 12))) }
        taper.locations = (0...12).map { NSNumber(value: Double($0) / 12) }
        taper.startPoint = CGPoint(x: 0, y: 0.5)
        taper.endPoint = CGPoint(x: 1, y: 0.5)
        group = AmbientCA.group(mask: AmbientCA.still(taper))
        lines = (0..<TideMath.lineCount).map { _ in AmbientCA.still(CALayer()) }
        shapes = lines.map { line in
            Self.strokes.map { stroke in
                let shape = AmbientCA.still(CAShapeLayer())
                shape.fillColor = nil
                shape.lineWidth = stroke.width
                shape.lineCap = .round
                shape.lineJoin = .round
                line.addSublayer(shape)
                return shape
            }
        }
        for line in lines {
            line.anchorPoint = .zero
            content.addSublayer(line)
        }
    }

    /// The share of a line's layer that one wavelength takes: the anchor point's travel per period. The layer is a
    /// light plus a wavelength wide, so this is the same at every width.
    static func travel(_ i: Int) -> Double { 1 / (1 + cycles(i)) }

    func layout(_ size: CGSize) {
        stopSwell()                                 // a swell drawn for the old size would jump
        self.size = size
        group.mask?.frame = CGRect(origin: .zero, size: size)
        for (i, line) in lines.enumerated() {
            let wavelength = max(size.width, 1) / CGFloat(Self.cycles(i))
            let base = size.height * CGFloat(0.80 + 0.06 * Double(i))
            line.bounds = CGRect(x: 0, y: 0, width: max(size.width, 1) + wavelength, height: 2 * Self.halfBand)
            line.position = CGPoint(x: 0, y: base - Self.halfBand)
            let path = Self.path(i, size: size, amplitudeScale: 1)
            for shape in shapes[i] {
                shape.frame = line.bounds
                shape.path = path
            }
        }
    }

    /// Line i's wave for a light of `size`, its amplitude `amplitudeScale` times the resting one.
    static func path(_ i: Int, size: CGSize, amplitudeScale: Double) -> CGPath {
        let width = max(size.width, 1)
        let wavelength = width / CGFloat(cycles(i))
        return wave(length: width + wavelength, wavelength: wavelength,
                    amplitude: CGFloat(amplitude(i) * amplitudeScale), phase: 2.1 * Double(i), midline: halfBand)
    }

    /// y(x) = midline + A · [sin(kx + φ) + 0.45 · sin(2kx − φ)], k = 2π / wavelength, every 2 pt over `length`. The
    /// second harmonic is twice the first (the shader's is 1.9 ×, which never repeats) so the path repeats every
    /// wavelength and the loop has no seam.
    static func wave(length: CGFloat, wavelength: CGFloat, amplitude: CGFloat, phase: Double,
                     midline: CGFloat) -> CGPath {
        let path = CGMutablePath()
        let k = 2 * Double.pi / Double(max(wavelength, 1))
        var x: CGFloat = 0
        while true {
            let a = k * Double(x)
            let y = midline + amplitude * CGFloat(sin(a + phase) + 0.45 * sin(2 * a - phase))
            if x == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
            if x >= length { break }
            x = min(x + 2, length)
        }
        return path
    }

    /// A line's strength inside the group: `TideMath.strength` over the cap.
    static func strength(_ level: AmbienceLevel) -> Double { 0.55 + 0.45 * level.intensity }

    func apply(glows: [RGB], level: AmbienceLevel) {
        let strength = Self.strength(level)
        for (i, strokes) in shapes.enumerated() {
            let rgb = AmbientCA.stop(glows, i)
            for (shape, stroke) in zip(strokes, Self.strokes) {
                shape.strokeColor = AmbientCA.color(rgb, min(1, strength * stroke.alpha))
            }
        }
    }

    func installAnimations(frameRate: Float) {
        for (i, line) in lines.enumerated() {
            line.add(AmbientCA.sweep("anchorPoint.x", from: 0, to: Self.travel(i), period: Self.period(i),
                                     phase: AmbientCA.hash(i + 200), frameRate: frameRate), forKey: "travel")
        }
    }

    /// The song change in place: every line's waves deepen to 2.1 × and settle (path keyframes the window server
    /// plays), instead of the whole tide lifting as a block. The strokes live under the clock, which runs while a swell
    /// starts; a paused clock holds the swell where it is, and `stopSwell` drops it before the clock jumps.
    func playSwell(elapsed: Double, frameRate: Float) -> Bool {
        guard size.width >= 1, size.height >= 1 else { return false }
        for (i, strokes) in shapes.enumerated() {
            let paths = Self.swellScales.map { Self.path(i, size: size, amplitudeScale: $0) }
            for shape in strokes {
                shape.add(AmbientCA.swell("path", values: paths, elapsed: elapsed, on: shape, frameRate: frameRate),
                          forKey: AmbientCA.swellKey)
            }
        }
        return true
    }

    func stopSwell() {
        for shape in shapes.joined() { shape.removeAnimation(forKey: AmbientCA.swellKey) }
    }

    var animatedLayers: [CALayer] { lines.filter { !($0.animationKeys() ?? []).isEmpty } }

    /// The stroke layers that hold a swell now (tests).
    var swellingLayers: [CALayer] { shapes.joined().filter { $0.animation(forKey: AmbientCA.swellKey) != nil } }
}

// MARK: - Halo

/// One still bloom of `glow1`: the Gaussian 0.6 · exp(−2.8 · (d/R)²) out to 1.5 R (`HaloFallback`'s stops), centred on
/// the placement. No animation.
final class HaloCA: AmbientCAEffect {
    let group = AmbientCA.group(mask: nil)
    let content = AmbientCA.still(CALayer())
    private let bloom = AmbientCA.ellipse()
    let placement: HaloPlacement

    init(placement: HaloPlacement) {
        self.placement = placement
        content.addSublayer(bloom)
    }

    func layout(_ size: CGSize) {
        let reach = placement.radius * 1.5
        bloom.bounds = CGRect(x: 0, y: 0, width: 2 * reach, height: 2 * reach)
        bloom.position = CGPoint(x: placement.center.x * size.width, y: placement.center.y * size.height)
    }

    func apply(glows: [RGB], level: AmbienceLevel) {
        let rgb = AmbientCA.stop(glows, 0)
        bloom.colors = (0...10).map { i in
            let x = Double(i) / 10 * 1.5
            return AmbientCA.color(rgb, 0.6 * exp(-2.8 * x * x))
        }
        bloom.locations = (0...10).map { NSNumber(value: Double($0) / 10) }
    }

    func installAnimations(frameRate: Float) {}

    var animatedLayers: [CALayer] { [] }
}
