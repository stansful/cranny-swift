// Rasterizes a notch canvas with ImageRenderer (final state of one-shot entrances, over a white backdrop)
// and finds the black shape in it, so tests can compare drawn sizes with DESIGN.md §3.3.
import CoreGraphics
import CrannyCore
import Foundation
import ImageIO
import SwiftUI
@testable import CrannyNotchUI

/// The drawn shape: dark pixels (luminance < 0.35) over the white backdrop. All values in points.
struct ShapeProbe {
    let width: Int, height: Int, scale: CGFloat
    private let pixels: [UInt8]

    init?(_ image: CGImage, scale: CGFloat) {
        let width = image.width, height = image.height
        self.width = width; self.height = height; self.scale = scale
        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        let ok = buffer.withUnsafeMutableBytes { raw -> Bool in
            guard let space = CGColorSpace(name: CGColorSpace.sRGB),
                  let ctx = CGContext(data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard ok else { return nil }
        pixels = buffer
    }

    /// Row 0 is the top of the canvas.
    func isDark(x: Int, y: Int) -> Bool { luminance(x: x, y: y) < 0.35 }

    /// Relative luminance (0…1) of a pixel; row 0 is the top of the canvas.
    func luminance(x: Int, y: Int) -> Double {
        let (r, g, b) = color(x: x, y: y)
        return 0.2126 * r + 0.7152 * g + 0.0722 * b
    }

    /// The pixel's red, green and blue (0…1, premultiplied over the opaque backdrop); row 0 is the top.
    func color(x: Int, y: Int) -> (r: Double, g: Double, b: Double) {
        let i = (y * width + x) * 4
        return (Double(pixels[i]) / 255, Double(pixels[i + 1]) / 255, Double(pixels[i + 2]) / 255)
    }

    /// Dark extent of the row at `y` points from the top (nil = none).
    func rowWidth(atPoint y: CGFloat) -> CGFloat? {
        let row = min(max(Int(y * scale), 0), height - 1)
        guard let first = (0..<width).first(where: { isDark(x: $0, y: row) }),
              let last = (0..<width).last(where: { isDark(x: $0, y: row) }) else { return nil }
        return CGFloat(last - first + 1) / scale
    }

    /// First and last dark rows of the centre column, in points (top, bottom edges).
    var verticalExtent: (top: CGFloat, bottom: CGFloat)? {
        let x = width / 2
        guard let first = (0..<height).first(where: { isDark(x: x, y: $0) }),
              let last = (0..<height).last(where: { isDark(x: x, y: $0) }) else { return nil }
        return (CGFloat(first) / scale, CGFloat(last + 1) / scale)
    }

    var hasDarkPixels: Bool { verticalExtent != nil }
}

@MainActor enum Snapshot {
    /// The canvas at `size` (default: the panel canvas) over white, rendered at 2× (right to left for Arabic and
    /// Hebrew panels).
    static func image(_ model: NotchSceneModel, _ registry: ModuleRegistry, size: CGSize? = nil,
                      background: Color = .white, scale: CGFloat = 2,
                      layoutDirection: LayoutDirection = .leftToRight) -> CGImage? {
        let canvas = size ?? model.layout.canvasSize
        let view = NotchCanvasView(model: model, registry: registry)
            .environment(\.notchRendersFinalState, true)
            .frame(width: canvas.width, height: canvas.height)
            .background(background)
            .environment(\.layoutDirection, layoutDirection)
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        return renderer.cgImage
    }

    static func probe(_ model: NotchSceneModel, _ registry: ModuleRegistry,
                      layoutDirection: LayoutDirection = .leftToRight) -> ShapeProbe? {
        image(model, registry, layoutDirection: layoutDirection).flatMap { ShapeProbe($0, scale: 2) }
    }

    /// Writes a PNG (for the opt-in gallery).
    static func write(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
    }
}
