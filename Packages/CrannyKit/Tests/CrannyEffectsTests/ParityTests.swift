import CoreGraphics
import CrannyCore
import Foundation
import SwiftUI
import Testing
@testable import CrannyEffects

// Shader + fallback parity (ARCHITECTURE.md §10.12): both paths of every ambient effect, rendered with the same
// palette, level, energy and time, agree on the black top 40 %, on peak alpha (±10 %), on the mean alpha of each
// horizontal third (±25 %) and on which stop dominates. The Metal layer must match the stitchable shader exactly.

private let size = CGSize(width: 880, height: 260)

private func render(_ effect: AmbientEffect, _ palette: AmbientPalette, _ level: AmbienceLevel,
                    time: Double) throws -> (shader: Raster, fallback: Raster) {
    (try rasterize(AmbientShader(effect: effect, glows: palette.glows, level: level, energy: 0, time: time,
                                 displayScale: 1), size: size),
     try rasterize(AmbientFallback(effect: effect, palette: palette, level: level, energy: 0, time: time), size: size))
}

/// Relative agreement within `tolerance`, or both below `floor` (a third that is (almost) dark on both paths).
private func agree(_ a: Double, _ b: Double, within tolerance: Double, floor: Double) -> Bool {
    if a < floor && b < floor { return true }
    return abs(a - b) <= tolerance * max(a, b)
}

@Test(.enabled(if: shadersRun), arguments: AmbientEffect.allCases)
func shaderAndFallbackAgree(_ effect: AmbientEffect) throws {
    for level in [AmbienceLevel.subtle, .vivid] {
        for time in [12.0, 40.0] {
            let (shader, fallback) = try render(effect, .afterglow, level, time: time)
            let cap = Glow.ambientAlphaCap(level)
            if effect != .halo {                                       // the halo blooms from the bottom edge, unbanded
                #expect(shader.peakAlpha(topRows: 0.4) == 0, "\(effect): shader lit the band")
                #expect(fallback.peakAlpha(topRows: 0.4) == 0, "\(effect): fallback lit the band")
            }
            #expect(agree(shader.peakAlpha, fallback.peakAlpha, within: 0.10, floor: 0),
                    "\(effect) \(level) t\(time): peak \(shader.peakAlpha) vs \(fallback.peakAlpha)")
            for third in 0..<3 {
                let from = Double(third) / 3, to = Double(third + 1) / 3
                let s = shader.meanAlpha(rows: from, to), f = fallback.meanAlpha(rows: from, to)
                #expect(agree(s, f, within: 0.25, floor: 0.01 * cap),
                        "\(effect) \(level) t\(time): third \(third) mean \(s) vs \(f)")
            }
        }
    }
}

/// The aurora's peak is ≈ 0.8 · cap at energy 0 on both paths (the mesh's brightest point).
@Test(.enabled(if: shadersRun)) func auroraPeaksAtFourFifthsOfTheCap() throws {
    for level in [AmbienceLevel.subtle, .vivid] {
        let (shader, fallback) = try render(.aurora, .afterglow, level, time: 12)
        let target = 0.8 * Glow.ambientAlphaCap(level)
        #expect(abs(shader.peakAlpha - target) <= 0.1 * target)
        #expect(abs(fallback.peakAlpha - target) <= 0.1 * target)
    }
}

/// Both paths lean toward the same stop: the stop nearest the light's mean colour is the same, for the palettes the
/// app shows most (the brand afterglow, the timer, monochrome, a tinted system accent and charging).
@Test(.enabled(if: shadersRun), arguments: [AmbientEffect.aurora, .motes, .tide])
func shaderAndFallbackShareTheDominantStop(_ effect: AmbientEffect) throws {
    let palettes: [AmbientPalette] = [.afterglow, .timer, .mono, .tinted(RGB(hex: 0x409CFF)), .charging]
    for palette in palettes {
        for time in [12.0, 40.0] {
            let (shader, fallback) = try render(effect, palette, .vivid, time: time)
            #expect(shader.nearestStopToMean(palette.glows) == fallback.nearestStopToMean(palette.glows),
                    "\(effect) t\(time): mean colours \(shader.meanColor) vs \(fallback.meanColor)")
        }
    }
}

/// The dedicated Metal layer draws exactly what the stitchable shader draws (same field code, same uniforms).
@Test(.enabled(if: shadersRun), arguments: AmbientEffect.allCases)
func metalLayerMatchesTheStitchableShader(_ effect: AmbientEffect) throws {
    for level in [AmbienceLevel.subtle, .vivid] {
        for energy in [0.0, 0.7] {
            let shader = try rasterize(AmbientShader(effect: effect, glows: AmbientPalette.afterglow.glows, level: level,
                                                     energy: energy, time: 23, displayScale: 1), size: size)
            let layer = try rasterizeLayer(layerState(effect, level: level, energy: energy), size: size, time: 23)
            #expect(layer.meanDifference(shader) < 0.5, "\(effect) \(level): \(layer.meanDifference(shader)) per channel")
            #expect(abs(layer.peakAlpha - shader.peakAlpha) <= 2.0 / 255)
        }
    }
}

/// The layer's fill and reveal uniforms match the SwiftUI masks of the other paths.
@Test(.enabled(if: shadersRun)) func layerMasksMatchTheSwiftUIMasks() throws {
    let palette = AmbientPalette.afterglow
    // Fill half-way: the light has risen from the bottom edge.
    let filled = try rasterize(AmbientShader(effect: .aurora, glows: palette.glows, level: .vivid, energy: 0, time: 12,
                                             displayScale: 1)
        .modifier(AmbientMasks(fill: 0.5, reveal: nil, reduceMotion: false)), size: size)
    let layerFilled = try rasterizeLayer(layerState(.aurora, level: .vivid, fill: 0.5), size: size, time: 12)
    #expect(agree(layerFilled.meanAlpha, filled.meanAlpha, within: 0.10, floor: 0))
    let layerFull = try rasterizeLayer(layerState(.aurora, level: .vivid), size: size, time: 12)
    #expect(layerFilled.meanAlpha(rows: 0.4, 0.55) < 0.6 * layerFull.meanAlpha(rows: 0.4, 0.55),
            "half filled: the upper light is still dim")
    #expect(abs(layerFilled.meanAlpha(rows: 0.85, 1) - layerFull.meanAlpha(rows: 0.85, 1)) < 0.01,
            "half filled: the bottom is already lit")
    // First light's reveal from the camera.
    let reveal = AmbientReveal(center: .top, radius: 300, feather: 120)
    let revealed = try rasterize(AmbientShader(effect: .aurora, glows: palette.glows, level: .vivid, energy: 0, time: 12,
                                               displayScale: 1)
        .modifier(AmbientMasks(fill: 1, reveal: reveal, reduceMotion: false)), size: size)
    var state = layerState(.aurora, level: .vivid)
    state.reveal = reveal
    let layerRevealed = try rasterizeLayer(state, size: size, time: 12)
    #expect(agree(layerRevealed.meanAlpha, revealed.meanAlpha, within: 0.10, floor: 0))
    #expect(layerRevealed.meanAlpha(columns: 0, 0.1) < 0.002, "outside the reveal stays dark")
    #expect(layerRevealed.meanAlpha(columns: 0.45, 0.55) > 0.05, "inside the reveal is lit")
}

/// Embers: the Canvas draws the same 18 particles as the shader (same hash, same kinematics).
@Test(.enabled(if: shadersRun)) func emberPathsAgree() throws {
    let origin = CGPoint(x: EmberBurst.size.width / 2, y: 0)
    let cap = Glow.ambientAlphaCap(.vivid)
    for t in [0.15, 0.45] {
        let shader = try rasterize(Rectangle().colorEffect(ShaderEffects.library.emberBurst(
            .boundingRect, .float2(origin), .float(t), .colorArray(AmbientPalette.timer.glows.map { $0.color(1) }),
            .float(cap))), size: EmberBurst.size)
        let canvas = try rasterize(EmberCanvas(glows: AmbientPalette.timer.glows, cap: cap, origin: origin, time: t),
                                   size: EmberBurst.size)
        // Same places: the lit pixels of one are mostly lit in the other.
        var overlap = 0, lit = 0
        for y in 0..<shader.height {
            for x in 0..<shader.width where shader.alpha(x, y) > 0.3 * cap {
                lit += 1
                if canvas.alpha(x, y) > 0.05 { overlap += 1 }
            }
        }
        #expect(lit > 20 && Double(overlap) / Double(lit) > 0.8, "t\(t): \(overlap) of \(lit) lit pixels shared")
        #expect(agree(shader.peakAlpha, canvas.peakAlpha, within: 0.35, floor: 0))
    }
}
