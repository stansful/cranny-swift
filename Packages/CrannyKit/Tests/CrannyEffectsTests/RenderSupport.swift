// Rasterizing helpers for the Effects tests: `ImageRenderer` draws stitchable shaders, MeshGradient and Canvas;
// `AmbientRenderer.image` draws the Metal layer's pipeline offscreen. Both end up as premultiplied sRGB RGBA8.
import CoreGraphics
import CrannyCore
import Foundation
import SwiftUI
import Testing
@testable import CrannyEffects

/// A premultiplied RGBA8 raster, row 0 = top.
struct Raster {
    let width: Int
    let height: Int
    let rgba: [UInt8]

    func alpha(_ x: Int, _ y: Int) -> Double { Double(rgba[(y * width + x) * 4 + 3]) / 255 }
    var alphas: [Double] { stride(from: 3, to: rgba.count, by: 4).map { Double(rgba[$0]) / 255 } }
    var peakAlpha: Double { alphas.max() ?? 0 }
    var meanAlpha: Double { alphas.reduce(0, +) / Double(max(alphas.count, 1)) }

    /// Mean alpha of rows `from ..< to` (fractions of the height).
    func meanAlpha(rows from: Double, _ to: Double) -> Double {
        let r0 = Int(Double(height) * from), r1 = Int(Double(height) * to)
        var sum = 0.0
        for y in r0..<r1 { for x in 0..<width { sum += alpha(x, y) } }
        return sum / Double(max((r1 - r0) * width, 1))
    }

    /// Mean alpha of columns `from ..< to` (fractions of the width).
    func meanAlpha(columns from: Double, _ to: Double) -> Double {
        let c0 = Int(Double(width) * from), c1 = Int(Double(width) * to)
        var sum = 0.0
        for y in 0..<height { for x in c0..<c1 { sum += alpha(x, y) } }
        return sum / Double(max((c1 - c0) * height, 1))
    }

    /// The largest alpha in the top `fraction` of the rows.
    func peakAlpha(topRows fraction: Double) -> Double {
        let rows = Int(Double(height) * fraction)
        return (0..<(rows * width)).map { Double(rgba[$0 * 4 + 3]) / 255 }.max() ?? 0
    }

    /// Alpha-weighted share of light closest to each stop (unpremultiplied colour, sRGB distance).
    func stopShares(_ stops: [RGB]) -> [Double] {
        var shares = [Double](repeating: 0, count: stops.count)
        for i in 0..<(width * height) {
            let a = Double(rgba[i * 4 + 3]) / 255
            guard a > 0.02 else { continue }
            let c = RGB(Double(rgba[i * 4]) / 255 / a, Double(rgba[i * 4 + 1]) / 255 / a, Double(rgba[i * 4 + 2]) / 255 / a)
            let nearest = stops.indices.min { (stops[$0] - c).magnitudeSquared < (stops[$1] - c).magnitudeSquared } ?? 0
            shares[nearest] += a
        }
        let total = max(shares.reduce(0, +), 1e-9)
        return shares.map { $0 / total }
    }

    /// Alpha-weighted mean of the unpremultiplied colour (the light's overall hue).
    var meanColor: RGB {
        var sum = RGB.zero
        var weight = 0.0
        for i in 0..<(width * height) {
            let a = Double(rgba[i * 4 + 3]) / 255
            guard a > 0.02 else { continue }
            sum = sum + RGB(Double(rgba[i * 4]) / 255, Double(rgba[i * 4 + 1]) / 255, Double(rgba[i * 4 + 2]) / 255)
            weight += a
        }
        guard weight > 0 else { return .zero }
        sum.scale(by: 1 / weight)
        return sum
    }

    /// The stop nearest the light's mean colour.
    func nearestStopToMean(_ stops: [RGB]) -> Int {
        let c = meanColor
        return stops.indices.min { (stops[$0] - c).magnitudeSquared < (stops[$1] - c).magnitudeSquared } ?? 0
    }

    func dominantStop(_ stops: [RGB]) -> Int {
        let shares = stopShares(stops)
        return shares.indices.max { shares[$0] < shares[$1] } ?? 0
    }

    /// Number of 4-connected regions of pixels with alpha ≥ `threshold` (the liquid neck's bodies).
    func components(alphaAtLeast threshold: Double = 0.5) -> Int {
        let solid = alphas.map { $0 >= threshold }
        var label = [Bool](repeating: false, count: solid.count)
        var count = 0
        for seed in solid.indices where solid[seed] && !label[seed] {
            count += 1
            var stack = [seed]
            label[seed] = true
            while let p = stack.popLast() {
                let x = p % width, y = p / width
                for (nx, ny) in [(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)]
                where nx >= 0 && ny >= 0 && nx < width && ny < height {
                    let q = ny * width + nx
                    if solid[q] && !label[q] { label[q] = true; stack.append(q) }
                }
            }
        }
        return count
    }

    /// Row (sub-pixel) where column `x` first reaches alpha 0.5 from the top, or the height when it never does.
    func topEdge(column x: Int) -> Double {
        var previous = 0.0
        for y in 0..<height {
            let a = alpha(x, y)
            if a >= 0.5 { return Double(y) - (a - 0.5) / max(a - previous, 1e-3) }
            previous = a
        }
        return Double(height)
    }

    /// Mean absolute difference per channel (0…255) against another raster of the same size, over the top
    /// `topRows` fraction of the rows (all of them by default).
    func meanDifference(_ other: Raster, topRows: Double = 1) -> Double {
        guard rgba.count == other.rgba.count else { return .infinity }
        let count = Int(Double(height) * topRows) * width * 4
        var sum = 0
        for i in 0..<count { sum += abs(Int(rgba[i]) - Int(other.rgba[i])) }
        return Double(sum) / Double(max(count, 1))
    }
}

/// Renders `view` at `size` points and `scale` into a premultiplied sRGB RGBA8 raster.
@MainActor func rasterize(_ view: some View, size: CGSize, scale: CGFloat = 1) throws -> Raster {
    let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height)
        .environment(\.effectRendering, .inline))
    renderer.scale = scale
    let image = try #require(renderer.cgImage)
    let (w, h) = (image.width, image.height)
    var data = [UInt8](repeating: 0, count: w * h * 4)
    let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
    let drawn: Bool = data.withUnsafeMutableBytes { buffer in
        guard let ctx = CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return true
    }
    try #require(drawn)
    return Raster(width: w, height: h, rgba: data)
}

/// Renders one frame of the ambient Metal layer's pipeline offscreen.
@MainActor func rasterizeLayer(_ state: AmbientLayerState, size: CGSize, scale: CGFloat = 1, time: Double,
                               date: Date = Date()) throws -> Raster {
    let renderer = try #require(AmbientRenderer.renderer(forDisplay: nil))
    let uniforms = AmbientUniforms(state: state, size: size, scale: scale, time: time, date: date)
    let w = Int(size.width * scale), h = Int(size.height * scale)
    let bgra = try #require(renderer.image(state.effect, uniforms: uniforms, width: w, height: h))
    var rgba = bgra
    for i in stride(from: 0, to: rgba.count, by: 4) { rgba.swapAt(i, i + 2) }
    return Raster(width: w, height: h, rgba: rgba)
}

/// Shaders can run here (a Metal device and the complete library).
nonisolated let shadersRun = ShaderEffects.isAvailable

/// Hardware-dependent checks (GPU time) run only with `CRANNY_INTEGRATION=1` (ARCHITECTURE.md §9.6), never in CI.
nonisolated let integrationTests = ProcessInfo.processInfo.environment["CRANNY_INTEGRATION"] == "1"

/// An open, running budget on AC.
nonisolated let runningBudget = EffectBudget(isOpen: true, onScreen: true, lowPower: false, fullScreenFront: false,
                                             reduceMotion: false, onBattery: false)

func layerState(_ effect: AmbientEffect, palette: AmbientPalette = .afterglow, level: AmbienceLevel = .subtle,
                energy: Double = 0, fill: Double = 1) -> AmbientLayerState {
    AmbientLayerState(effect: effect, glows: palette.glows, energy: energy, level: level, fill: fill, reveal: nil,
                      rippleStart: nil, halo: .ambient, interval: 1.0 / 30, restingTime: 7.3)
}
