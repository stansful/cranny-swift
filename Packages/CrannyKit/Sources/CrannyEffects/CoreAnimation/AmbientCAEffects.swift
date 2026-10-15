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
//   opacities) or fixed point offsets, so a resize changes the layers' geometry but never an animation.
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

    /// The band mask of the aurora's SwiftUI fallback (`BandMask`): clear over the top 40 %, opaque from 48 %.
    static func bandMask() -> CAGradientLayer {
        verticalMask([(0, 0), (0.40, 0), (0.48, 1), (1, 1)])
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

/// Soft curtains of palette light rising from the bottom edge: four wide glows along the edge (stops 3 · 1 · 2 · 3
/// from left to right, as the fallback mesh's bottom row) and four narrow rays above them (1 · 2 · 3 · 1). Each is
/// the radial gradient of an ellipse centred on the bottom edge; it drifts sideways, breathes in height and, for the
/// rays, in brightness, each on its own period (8–59 s a cycle).
final class AuroraCA: AmbientCAEffect {
    /// One curtain: where it stands (fractions of the light's size) and how it moves.
    nonisolated struct Curtain: Equatable, Sendable {
        var x: Double              // centre, fraction of the width
        var halfWidth: Double      // fraction of the width
        var halfHeight: Double     // fraction of the height (the curtain's top at rest: 1 − halfHeight)
        var stop: Int
        var isRay: Bool
        var drift: Double          // anchor-point travel, ± fraction of the curtain's own width
        var driftPeriod: Double
        var swell: ClosedRange<Double>   // height scale
        var swellPeriod: Double
        var glow: ClosedRange<Double>    // opacity
        var glowPeriod: Double
    }

    /// The curtains, back to front. Each stands on the bottom edge and reaches about 62 % of the light's height, so it
    /// fades out where the band mask begins (the top 40 % stays clear whatever the swell does).
    static let curtains: [Curtain] = [
        Curtain(x: 0.00, halfWidth: 0.32, halfHeight: 0.60, stop: 2, isRay: false, drift: 0.06, driftPeriod: 47.4,
                swell: 0.90...1.05, swellPeriod: 26.6, glow: 0.85...1, glowPeriod: 19.4),
        Curtain(x: 0.35, halfWidth: 0.28, halfHeight: 0.63, stop: 0, isRay: false, drift: 0.07, driftPeriod: 58.6,
                swell: 0.88...1.04, swellPeriod: 35.8, glow: 0.85...1, glowPeriod: 23.0),
        Curtain(x: 0.66, halfWidth: 0.28, halfHeight: 0.62, stop: 1, isRay: false, drift: 0.07, driftPeriod: 38.2,
                swell: 0.89...1.05, swellPeriod: 23.4, glow: 0.85...1, glowPeriod: 29.8),
        Curtain(x: 1.00, halfWidth: 0.32, halfHeight: 0.60, stop: 2, isRay: false, drift: 0.06, driftPeriod: 53.8,
                swell: 0.90...1.05, swellPeriod: 30.2, glow: 0.85...1, glowPeriod: 21.6),
        Curtain(x: 0.14, halfWidth: 0.07, halfHeight: 0.64, stop: 0, isRay: true, drift: 0.45, driftPeriod: 33.4,
                swell: 0.84...1.04, swellPeriod: 14.6, glow: 0.45...1, glowPeriod: 11.8),
        Curtain(x: 0.42, halfWidth: 0.09, halfHeight: 0.63, stop: 1, isRay: true, drift: 0.40, driftPeriod: 41.8,
                swell: 0.82...1.04, swellPeriod: 17.8, glow: 0.45...1, glowPeriod: 9.4),
        Curtain(x: 0.61, halfWidth: 0.08, halfHeight: 0.64, stop: 2, isRay: true, drift: 0.42, driftPeriod: 29.0,
                swell: 0.84...1.03, swellPeriod: 12.2, glow: 0.45...1, glowPeriod: 13.6),
        Curtain(x: 0.87, halfWidth: 0.07, halfHeight: 0.63, stop: 0, isRay: true, drift: 0.45, driftPeriod: 37.6,
                swell: 0.83...1.04, swellPeriod: 15.8, glow: 0.45...1, glowPeriod: 7.8),
    ]

    let group: CALayer
    let content = AmbientCA.still(CALayer())
    private let layers: [CAGradientLayer]

    init() {
        group = AmbientCA.group(mask: AmbientCA.bandMask())
        layers = Self.curtains.map { _ in AmbientCA.ellipse() }
        for layer in layers { content.addSublayer(layer) }
    }

    /// Peak alpha (inside the group) of a curtain: the wide glows hold the edge, the rays add structure, more of it
    /// at Vivid (DESIGN.md §5.6 rule 3: intensity scales structure, never the ceiling).
    static func peak(_ curtain: Curtain, level: AmbienceLevel) -> Double {
        curtain.isRay ? 0.35 + 0.30 * level.intensity : 0.70
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
            let bump = AmbientCA.curtain(AmbientCA.stop(glows, curtain.stop), peak: Self.peak(curtain, level: level))
            layer.colors = bump.colors
            layer.locations = bump.locations
        }
    }

    func installAnimations(frameRate: Float) {
        for (i, (layer, c)) in zip(layers, Self.curtains).enumerated() {
            layer.add(AmbientCA.breath("anchorPoint.x", from: 0.5 - c.drift / 2, to: 0.5 + c.drift / 2,
                                       period: c.driftPeriod, phase: AmbientCA.hash(i), frameRate: frameRate),
                      forKey: "drift")
            layer.add(AmbientCA.breath("transform.scale.y", from: c.swell.lowerBound, to: c.swell.upperBound,
                                       period: c.swellPeriod, phase: AmbientCA.hash(i + 8), frameRate: frameRate),
                      forKey: "swell")
            layer.add(AmbientCA.breath("opacity", from: c.glow.lowerBound, to: c.glow.upperBound,
                                       period: c.glowPeriod, phase: AmbientCA.hash(i + 16), frameRate: frameRate),
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
    /// The light's usual height: a mote's period is its speed over this span, so it rises at 5–14 pt/s in a light of
    /// this height and proportionally faster or slower in others (the animation stays a fraction of the height).
    static let referenceHeight: CGFloat = 240

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
/// a path a light and a wavelength wide, stroked as a 1.5-pt core over two wider, fainter blooms, travelling one
/// wavelength to the left per period (seamless: the path repeats every wavelength). A horizontal mask thins the
/// lines toward both ends, as the shader's taper.
final class TideCA: AmbientCAEffect {
    /// Line i's wavelength in widths of the light (`TideMath`'s spatial rate 0.75 + 0.35 i per width).
    static func cycles(_ i: Int) -> Double { 0.75 + 0.35 * Double(i) }
    /// Seconds per wavelength (`TideMath`'s temporal rate 0.09 + 0.035 i).
    static func period(_ i: Int) -> Double { 1 / (0.09 + 0.035 * Double(i)) }
    /// Amplitude at energy 0 (`TideMath.line`: (3 + 7 · energy) · (1 − 0.2 · i) pt).
    static func amplitude(_ i: Int) -> Double { 3 * (1 - 0.2 * Double(i)) }
    /// The strokes of one line: width (pt) and alpha relative to the line's strength.
    static let strokes: [(width: CGFloat, alpha: Double)] = [(10, 0.10), (5, 0.24), (1.5, 0.92)]
    /// Points above and below the line that its strokes and waves can reach.
    static let halfBand: CGFloat = 12

    let group: CALayer
    let content = AmbientCA.still(CALayer())
    /// One travelling layer per line, holding its strokes.
    private let lines: [CALayer]
    private let shapes: [[CAShapeLayer]]

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
        group.mask?.frame = CGRect(origin: .zero, size: size)
        let width = max(size.width, 1)
        for (i, line) in lines.enumerated() {
            let wavelength = width / CGFloat(Self.cycles(i))
            let base = size.height * CGFloat(0.80 + 0.06 * Double(i))
            line.bounds = CGRect(x: 0, y: 0, width: width + wavelength, height: 2 * Self.halfBand)
            line.position = CGPoint(x: 0, y: base - Self.halfBand)
            let path = Self.wave(length: width + wavelength, wavelength: wavelength,
                                 amplitude: CGFloat(Self.amplitude(i)), phase: 2.1 * Double(i), midline: Self.halfBand)
            for shape in shapes[i] {
                shape.frame = line.bounds
                shape.path = path
            }
        }
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
                shape.strokeColor = AmbientCA.color(rgb, strength * stroke.alpha)
            }
        }
    }

    func installAnimations(frameRate: Float) {
        for (i, line) in lines.enumerated() {
            line.add(AmbientCA.sweep("anchorPoint.x", from: 0, to: Self.travel(i), period: Self.period(i),
                                     phase: AmbientCA.hash(i + 200), frameRate: frameRate), forKey: "travel")
        }
    }

    var animatedLayers: [CALayer] { lines.filter { !($0.animationKeys() ?? []).isEmpty } }
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
