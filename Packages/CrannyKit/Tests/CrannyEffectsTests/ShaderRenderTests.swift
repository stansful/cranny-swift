import CoreGraphics
import CrannyCore
import Foundation
import Metal
import SwiftUI
import Testing
@testable import CrannyEffects

// A missing stitchable function or a uniform mismatch renders TRANSPARENT without an error (DESIGN.md §5.6), so every
// function in `ShaderEffects.requiredFunctions` gets a render test: `ImageRenderer` rasterizes the stitchable ones,
// `AmbientRenderer.image` the layer pipeline. Plus the alpha cap on every path (ARCHITECTURE.md §10.12).

private let size = CGSize(width: 880, height: 260)

@Test(.enabled(if: shadersRun)) func auroraFieldKeepsTheBandBlackAndStaysUnderTheCap() throws {
    for level in [AmbienceLevel.subtle, .vivid] {
        let r = try rasterize(AmbientShader(effect: .aurora, glows: AmbientPalette.afterglow.glows, level: level,
                                            energy: 0, time: 12, displayScale: 1), size: size)
        let bandRows = Int(Double(r.height) * 0.40)
        #expect(r.alphas[0..<(bandRows * r.width)].allSatisfy { $0 == 0 }, "the top 40 % must stay black")
        let cap = Glow.ambientAlphaCap(level) * 255
        let peak = r.peakAlpha * 255
        #expect(peak <= cap.rounded(.up), "peak \(peak) over the cap \(cap)")
        #expect(peak >= 0.5 * cap, "peak \(peak): the shader drew (almost) nothing")
    }
}

@Test(.enabled(if: shadersRun)) func crannyDitherKeepsCoverage() throws {
    // Left half transparent, right half 50 % grey (a fully empty view is not a fair input: SwiftUI skips it).
    let r = try rasterize(HStack(spacing: 0) { Color.clear; Color(white: 0.25, opacity: 0.5) }.crannyDithered(scale: 1),
                          size: CGSize(width: 64, height: 64))
    for row in 0..<r.height {
        for column in 0..<r.width {
            let a = Int(r.rgba[(row * r.width + column) * 4 + 3])
            if column < 31 { #expect(a == 0, "transparent stays transparent") }
            if column > 32 { #expect(abs(a - 128) <= 1, "coverage is untouched") }
        }
    }
}

/// `auroraField`, `tideField`, `motesField`, `haloGlow` and the four layer fragments draw something.
@Test(.enabled(if: shadersRun), arguments: AmbientEffect.allCases)
func everyAmbientFunctionDraws(_ effect: AmbientEffect) throws {
    let stitchable = try rasterize(AmbientShader(effect: effect, glows: AmbientPalette.afterglow.glows, level: .vivid,
                                                 energy: 0.5, time: 12, displayScale: 1), size: size)
    #expect(stitchable.peakAlpha > 0.2, "\(effect): stitchable function drew nothing")
    let layer = try rasterizeLayer(layerState(effect, level: .vivid, energy: 0.5), size: size, time: 12)
    #expect(layer.peakAlpha > 0.2, "\(effect): \(AmbientRenderer.fragmentName(effect)) drew nothing")
}

/// The alpha cap holds on the Metal layer, the stitchable shader and the fallback, at both levels, at rest, at full
/// energy and under the ripple's energy pulse (1.5).
@Test(.enabled(if: shadersRun), arguments: AmbientEffect.allCases)
func ambientLightNeverPassesTheCap(_ effect: AmbientEffect) throws {
    for level in [AmbienceLevel.subtle, .vivid] {
        let cap = Glow.ambientAlphaCap(level) + 1.0 / 255                // 8-bit rounding
        for energy in [0.0, 1.5] {
            for time in [41.0] {
                let shader = try rasterize(AmbientShader(effect: effect, glows: AmbientPalette.timer.glows, level: level,
                                                         energy: energy, time: time, displayScale: 1), size: size)
                let fallback = try rasterize(AmbientFallback(effect: effect, palette: .timer, level: level,
                                                             energy: energy, time: time), size: size)
                let layer = try rasterizeLayer(layerState(effect, palette: .timer, level: level, energy: energy),
                                               size: size, time: time)
                #expect(shader.peakAlpha <= cap, "\(effect) \(level) shader \(shader.peakAlpha)")
                #expect(fallback.peakAlpha <= cap, "\(effect) \(level) fallback \(fallback.peakAlpha)")
                #expect(layer.peakAlpha <= cap, "\(effect) \(level) layer \(layer.peakAlpha)")
            }
        }
        // Low Power's static halo and the macOS 14 curtains.
        let halo = try rasterize(HaloFallback(glow: .white, level: level, placement: .ambient), size: size)
        #expect(halo.peakAlpha <= cap && halo.peakAlpha > 0.5 * Glow.ambientAlphaCap(level))
        let curtains = try rasterize(AuroraCurtains(palette: .timer, level: level, energy: 1, time: 5)
            .mask { BandMask() }, size: size)
        #expect(curtains.peakAlpha <= cap && curtains.peakAlpha > 0.1, "macOS 14 curtains \(curtains.peakAlpha)")
        #expect(curtains.peakAlpha(topRows: 0.4) == 0, "macOS 14 curtains keep the band black")
    }
}

/// `songRipple` displaces the light while it plays and leaves it alone afterwards.
@Test(.enabled(if: shadersRun)) func songRippleDistortsOnlyWhilePlaying() throws {
    func frame(_ elapsed: Double?) throws -> Raster {
        try rasterize(AmbientShader(effect: .aurora, glows: AmbientPalette.afterglow.glows, level: .vivid, energy: 0,
                                    time: 12, displayScale: 1).modifier(RippleDistortion(elapsed: elapsed)), size: size)
    }
    let still = try frame(nil)
    #expect(try frame(0.25).meanDifference(still) > 0.05, "the ripple moved nothing")
    #expect(try frame(0.6).meanDifference(still) < 0.01, "the ripple is over at 0.6 s")
}

/// `liquidNeck` joins two bodies across a small gap early in the split and lets go at the end.
@Test(.enabled(if: shadersRun)) func liquidNeckJoinsThenSnaps() throws {
    let budget = runningBudget
    func gapAlpha(_ progress: Double, shader: Bool) throws -> Double {
        let bodies = HStack(spacing: 6) {
            Rectangle().fill(.black).frame(width: 40, height: 30)
            Rectangle().fill(.black).frame(width: 40, height: 30)
        }
        .frame(width: 100, height: 50)
        let view: AnyView = shader
            ? AnyView(LiquidNeck(progress: progress, budget: budget) { bodies })
            : AnyView(LiquidNeck(progress: progress, budget: EffectBudget(isOpen: true, onScreen: true, lowPower: true,
                                                                          fullScreenFront: false, reduceMotion: false,
                                                                          onBattery: false)) { bodies })
        let r = try rasterize(view, size: CGSize(width: 100, height: 50))
        return r.alpha(50, 25)                                          // the middle of the 6-pt gap
    }
    for shader in [true, false] {
        #expect(try gapAlpha(0.1, shader: shader) > 0.9, "\(shader ? "shader" : "Canvas"): no neck early on")
        #expect(try gapAlpha(1.0, shader: shader) < 0.1, "\(shader ? "shader" : "Canvas"): the neck did not snap")
    }
}

/// `emberBurst` draws embers near the notch while they burn, under the cap, and nothing once they are out.
@Test(.enabled(if: shadersRun)) func emberBurstBurnsOutUnderTheCap() throws {
    let origin = CGPoint(x: EmberBurst.size.width / 2, y: 0)
    for level in [AmbienceLevel.off, .vivid] {
        let cap = Glow.ambientAlphaCap(max(level, .subtle))
        func frame(_ t: Double) throws -> Raster {
            try rasterize(Rectangle().colorEffect(ShaderEffects.library.emberBurst(
                .boundingRect, .float2(origin), .float(t), .colorArray(AmbientPalette.timer.glows.map { $0.color(1) }),
                .float(cap))), size: EmberBurst.size)
        }
        let burning = try frame(0.3)
        #expect(burning.peakAlpha > 0.5 * cap && burning.peakAlpha <= cap + 1.0 / 255)
        #expect(try frame(0.95).peakAlpha == 0)
        let canvas = try rasterize(EmberCanvas(glows: AmbientPalette.timer.glows, cap: cap, origin: origin, time: 0.3),
                                   size: EmberBurst.size)
        #expect(canvas.peakAlpha > 0.3 * cap && canvas.peakAlpha <= cap + 1.0 / 255)
    }
}

/// `chargeSweep` lights the rim around the head, under the cap; the fallback trim lights the same stretch.
@Test(.enabled(if: shadersRun)) func chargeSweepLightsTheHead() throws {
    var outline = Path()
    outline.move(to: CGPoint(x: 10, y: 20))
    outline.addLine(to: CGPoint(x: 290, y: 20))
    let cap = Glow.ambientAlphaCap(.vivid)
    let shader = try rasterize(SweepShader(outline: outline, glow: AmbientPalette.charging.glow1, cap: cap, progress: 0.5),
                               size: CGSize(width: 300, height: 40))
    let fallback = try rasterize(SweepTrim(outline: outline, glow: AmbientPalette.charging.glow1, cap: cap, progress: 0.5),
                                 size: CGSize(width: 300, height: 40))
    for r in [shader, fallback] {
        #expect(r.peakAlpha <= cap + 1.0 / 255 && r.peakAlpha > 0.5 * cap)
        #expect(r.alpha(150, 20) > 0.5 * cap, "the head is half-way at progress 0.5")
        #expect(r.alpha(270, 20) < 0.05, "nothing ahead of the head")
    }
}

/// `haloGlow` peaks at 0.6 · cap at its centre, on the stitchable and the layer path.
@Test(.enabled(if: shadersRun)) func haloGlowPeaksAtItsCentre() throws {
    let placement = HaloPlacement(center: .center, radius: 80)
    let cap = Glow.ambientAlphaCap(.vivid)
    let shader = try rasterize(AmbientShader(effect: .halo, glows: [.white], level: .vivid, energy: 0, time: 0,
                                             halo: placement, displayScale: 1), size: CGSize(width: 200, height: 200))
    var state = layerState(.halo, level: .vivid)
    state.halo = placement
    let layer = try rasterizeLayer(state, size: CGSize(width: 200, height: 200), time: 0)
    for r in [shader, layer] {
        #expect(abs(r.alpha(100, 100) - 0.6 * cap) < 0.01)
        #expect(r.alpha(0, 0) < 0.02)
    }
}
