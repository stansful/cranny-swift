import CoreGraphics
import CrannyCore
import Metal
import SwiftUI
import Testing
@testable import CrannyEffects

// A missing stitchable function or a uniform mismatch renders TRANSPARENT without an error (DESIGN.md §5.6),
// so every function in `ShaderEffects.requiredFunctions` gets a render test. `ImageRenderer` rasterizes them.

/// Alpha of every pixel (premultiplied RGBA8, row 0 = top).
@MainActor private func alphas(of view: some View, size: CGSize) throws -> (width: Int, height: Int, alpha: [UInt8]) {
    let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height))
    renderer.scale = 1
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
    return (w, h, stride(from: 3, to: data.count, by: 4).map { data[$0] })
}

nonisolated private let shadersRun = MTLCreateSystemDefaultDevice() != nil && ShaderEffects.isAvailable

@Test(.enabled(if: shadersRun)) func auroraFieldKeepsTheBandBlackAndStaysUnderTheCap() throws {
    for level in [AmbienceLevel.subtle, .vivid] {
        let r = try alphas(of: auroraShader(palette: .afterglow, level: level, energy: 0, time: 12, displayScale: 1),
                           size: CGSize(width: 880, height: 260))
        let bandRows = Int(Double(r.height) * 0.40)
        #expect(r.alpha[0..<(bandRows * r.width)].allSatisfy { $0 == 0 }, "the top 40 % must stay black")
        let cap = Glow.ambientAlphaCap(level) * 255
        let peak = Double(r.alpha.max() ?? 0)
        #expect(peak <= cap.rounded(.up), "peak \(peak) over the cap \(cap)")
        #expect(peak >= 0.5 * cap, "peak \(peak): the shader drew (almost) nothing")
    }
}

@Test(.enabled(if: shadersRun)) func crannyDitherKeepsCoverage() throws {
    // Left half transparent, right half 50 % grey (a fully empty view is not a fair input: SwiftUI skips it).
    let r = try alphas(of: HStack(spacing: 0) { Color.clear; Color(white: 0.25, opacity: 0.5) }.crannyDithered(scale: 1),
                       size: CGSize(width: 64, height: 64))
    for row in 0..<r.height {
        for column in 0..<r.width {
            let a = Int(r.alpha[row * r.width + column])
            if column < 31 { #expect(a == 0, "transparent stays transparent") }
            if column > 32 { #expect(abs(a - 128) <= 1, "coverage is untouched") }
        }
    }
}
