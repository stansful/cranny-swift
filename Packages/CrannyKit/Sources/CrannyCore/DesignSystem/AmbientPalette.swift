// CrannyCore/DesignSystem/AmbientPalette.swift
// Content-derived light palette + the energy budget contract (moved from DESIGN.md Appendix B so that
// CrannyMedia, CrannyEffects and the shell can all use them without importing each other).
import SwiftUI
import CoreGraphics

// MARK: - Palette from content

/// `glow1…3` are LIGHT (aurora, halo, underglow) and are clamped by `Glow` caps.
/// `accent` is a FOREGROUND mark and is contrast-guarded. Never put text on a glow without a card or scrim.
public nonisolated struct AmbientPalette: Equatable, Sendable {
    public var glow1: RGB, glow2: RGB, glow3: RGB
    public var accent: RGB
    public var isMonochrome: Bool

    public init(glow1: RGB, glow2: RGB, glow3: RGB, accent: RGB, isMonochrome: Bool = false) {
        self.glow1 = glow1; self.glow2 = glow2; self.glow3 = glow3; self.accent = accent; self.isMonochrome = isMonochrome
    }
    public var glows: [RGB] { [glow1, glow2, glow3] }

    /// Animatable form, so a track change cross-fades the light (`CrannyMotion.Kind.colorShift`).
    public typealias Vector = AnimatablePair<AnimatablePair<RGB, RGB>, AnimatablePair<RGB, RGB>>
    public var vector: Vector {
        get { .init(.init(glow1, glow2), .init(glow3, accent)) }
        set { glow1 = newValue.first.first; glow2 = newValue.first.second
              glow3 = newValue.second.first; accent = newValue.second.second }
    }

    // Palettes for activities without artwork (per-activity light, never random).
    public static let afterglow = AmbientPalette(glow1: BrandColor.iris, glow2: BrandColor.lagoon, glow3: BrandColor.rose, accent: RGB(hex: 0xA996FF))
    public static let timer = AmbientPalette(glow1: BrandColor.ember, glow2: RGB(hex: 0xFFB347), glow3: BrandColor.rose, accent: RGB(hex: 0xFF9F0A))
    public static let charging = AmbientPalette(glow1: RGB(hex: 0x30D158), glow2: RGB(hex: 0x9CF06B), glow3: BrandColor.lagoon, accent: RGB(hex: 0x30D158))
    public static let lowBattery = AmbientPalette(glow1: RGB(hex: 0xFF453A), glow2: BrandColor.ember, glow3: BrandColor.rose, accent: RGB(hex: 0xFF6961))
    public static let mono = AmbientPalette(glow1: RGB(0.78, 0.80, 0.86), glow2: RGB(0.55, 0.58, 0.66),
                                            glow3: RGB(0.90, 0.90, 0.95), accent: RGB(0.94, 0.94, 0.96), isMonochrome: true)
    /// Calendar event colour or the system accent → three analogous glows.
    public static func tinted(_ c: RGB) -> AmbientPalette {
        let (h, s, v) = c.hsb
        return .init(glow1: c.luminous,
                     glow2: RGB(h: (h + 0.06).truncatingRemainder(dividingBy: 1), s: s, v: v).luminous,
                     glow3: RGB(h: (h + 0.94).truncatingRemainder(dividingBy: 1), s: s * 0.8, v: v).luminous,
                     accent: c.legible())
    }

    /// Deterministic k-means (k = 5, 8 iterations) on a 24×24 thumbnail. ~0.1–0.3 ms.
    /// Run off the main actor; cache by track identifier; greyscale art → honest `.mono`.
    public static func extract(from image: CGImage) -> AmbientPalette {
        let side = 24
        var px = [UInt8](repeating: 0, count: side * side * 4)
        let ok: Bool = px.withUnsafeMutableBytes { buf in
            guard let space = CGColorSpace(name: CGColorSpace.sRGB),
                  let ctx = CGContext(data: buf.baseAddress, width: side, height: side, bitsPerComponent: 8,
                                      bytesPerRow: side * 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.interpolationQuality = .medium
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard ok else { return .afterglow }
        var samples: [RGB] = []
        samples.reserveCapacity(side * side)
        for i in stride(from: 0, to: px.count, by: 4) where px[i + 3] > 200 {
            samples.append(RGB(Double(px[i]) / 255, Double(px[i + 1]) / 255, Double(px[i + 2]) / 255))
        }
        guard samples.count > 16 else { return .afterglow }

        let k = 5
        var centers = (0..<k).map { samples[$0 * samples.count / k] }
        var counts = [Int](repeating: 0, count: k)
        for _ in 0..<8 {
            var sums = [RGB](repeating: .zero, count: k)
            counts = [Int](repeating: 0, count: k)
            for s in samples {
                var best = 0, bestD = Double.infinity
                for (j, c) in centers.enumerated() {
                    let d = (s - c).magnitudeSquared
                    if d < bestD { bestD = d; best = j }
                }
                sums[best] = sums[best] + s; counts[best] += 1
            }
            for j in 0..<k where counts[j] > 0 { var c = sums[j]; c.scale(by: 1 / Double(counts[j])); centers[j] = c }
        }
        func chroma(_ c: RGB) -> Double { max(c.r, c.g, c.b) - min(c.r, c.g, c.b) }
        let total = Double(samples.count)
        func score(_ c: RGB, _ w: Double) -> Double {
            let (_, s, v) = c.hsb
            let penalty = (v < 0.12 || (s < 0.08 && v > 0.9)) ? 0.15 : 1
            return w * (0.25 + chroma(c)) * penalty
        }
        let ranked = zip(centers, counts).filter { $0.1 > 0 }
            .map { (c: $0.0, w: Double($0.1) / total) }
            .sorted { score($0.c, $0.w) > score($1.c, $1.w) }
        if (ranked.map { chroma($0.c) }.max() ?? 0) < 0.10 { return .mono }

        var picks: [RGB] = []
        for cand in ranked.map(\.c) {
            let h = cand.hsb.h
            if picks.allSatisfy({ let d = abs($0.hsb.h - h); return d > 0.06 && d < 0.94 }) { picks.append(cand) }
            if picks.count == 3 { break }
        }
        while picks.count < 3, let base = picks.first?.hsb {   // single-hued art → analogous neighbours
            let shift = picks.count == 1 ? 0.07 : -0.07
            picks.append(RGB(h: (base.h + shift + 1).truncatingRemainder(dividingBy: 1), s: base.s, v: base.v))
        }
        let vivid = ranked.map(\.c).max { chroma($0) < chroma($1) } ?? picks[0]
        return .init(glow1: picks[0].luminous, glow2: picks[1].luminous, glow3: picks[2].luminous,
                     accent: vivid.legible())
    }
}

// MARK: - Energy budget (contract)

public nonisolated struct EffectBudget: Equatable, Sendable {
    public var isOpen: Bool             // ambient runs only while the Nook is open
    public var onScreen: Bool           // panel visible and not occluded (NSWindow.occlusionState)
    public var lowPower: Bool           // ProcessInfo.isLowPowerModeEnabled || thermalState ≥ .serious
    public var fullScreenFront: Bool
    public var reduceMotion: Bool
    public var onBattery: Bool
    public init(isOpen: Bool, onScreen: Bool, lowPower: Bool, fullScreenFront: Bool, reduceMotion: Bool, onBattery: Bool) {
        self.isOpen = isOpen; self.onScreen = onScreen; self.lowPower = lowPower
        self.fullScreenFront = fullScreenFront; self.reduceMotion = reduceMotion; self.onBattery = onBattery
    }
    /// nil = paused → TimelineView stops ticking (zero cost). Reduce Motion FREEZES a resting frame.
    public var minimumInterval: Double? {
        guard isOpen, onScreen, !fullScreenFront, !reduceMotion, !lowPower else { return nil }
        return onBattery ? 1.0 / 20 : 1.0 / 30
    }
    /// Low Power Mode downgrades every effect to the static halo.
    public func effective(_ e: AmbientEffect) -> AmbientEffect { lowPower ? .halo : e }
}

