// Rendering the Core Animation light (Appearance ▸ Quality ▸ Efficient) offscreen for the Effects tests: `CARenderer`
// draws a layer tree with its masks, group opacity and animations at a given time into a Metal texture, as the window
// server would. Only the tests use Metal here; the app's Core Animation light never does.
import AppKit
import CoreGraphics
import CrannyCore
import Foundation
import Metal
import QuartzCore
import Testing
@testable import CrannyEffects

/// A Core Animation light of `effect` at `level`, standing still on the light's time `time` (the resting frame), in a
/// view of `size` points (never shown).
@MainActor func caView(_ effect: AmbientEffect, palette: AmbientPalette = .afterglow, level: AmbienceLevel = .subtle,
                       size: CGSize = CGSize(width: 640, height: 240), time: Double = 7.3, fill: Double = 1,
                       interval: Double? = 1.0 / 30, rests: Bool = true) -> AmbientCANSView {
    let view = AmbientCANSView()
    view.frame = CGRect(origin: .zero, size: size)
    view.state = caState(effect, palette: palette, level: level, time: time, fill: fill, interval: interval, rests: rests)
    return view
}

func caState(_ effect: AmbientEffect, palette: AmbientPalette = .afterglow, level: AmbienceLevel = .subtle,
             time: Double = 7.3, fill: Double = 1, interval: Double? = 1.0 / 30, rests: Bool = false,
             crossFade: AmbientCAFade? = nil) -> AmbientCAState {
    AmbientCAState(effect: effect, glows: palette.glows, level: level, fill: fill, interval: interval, rests: rests,
                   restingTime: time, halo: .ambient, rippleStart: nil, crossFade: crossFade)
}

/// Renders the light of `view` (its fill layer and everything under it) at `scale` pixels per point into a premultiplied
/// sRGB RGBA8 raster, row 0 = top. The tree is lent to a flipped container for the render and given back.
@MainActor func rasterizeCA(_ view: AmbientCANSView, scale: CGFloat = 1) throws -> Raster {
    let light = view.lightLayer
    let parent = try #require(light.superlayer)
    let size = view.bounds.size
    let container = CALayer()
    container.isGeometryFlipped = true
    container.frame = CGRect(origin: .zero, size: size)
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    container.addSublayer(light)
    CATransaction.commit()
    defer {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        parent.addSublayer(light)
        CATransaction.commit()
    }
    return try rasterize(layer: container, size: size, scale: scale)
}

/// Renders any layer tree whose root is `size` points at `scale` with `CARenderer`; row 0 of the raster is the top.
@MainActor func rasterize(layer: CALayer, size: CGSize, scale: CGFloat) throws -> Raster {
    let device = try #require(AmbientGPU.device(), "no Metal device")
    let queue = try #require(device.makeCommandQueue())
    let w = Int(size.width * scale), h = Int(size.height * scale)
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: w, height: h, mipmapped: false)
    descriptor.usage = [.renderTarget, .shaderRead]
    descriptor.storageMode = .managed
    let texture = try #require(device.makeTexture(descriptor: descriptor))
    let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
    let renderer = CARenderer(mtlTexture: texture, options: [kCARendererColorSpace as String: space,
                                                             kCARendererMetalCommandQueue as String: queue])
    let root = CALayer()
    root.frame = CGRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h))
    layer.transform = CATransform3DMakeScale(scale, scale, 1)
    layer.anchorPoint = .zero
    layer.position = .zero
    root.addSublayer(layer)
    renderer.layer = root
    renderer.bounds = root.frame
    CATransaction.flush()                                  // the renderer sees committed layers only
    renderer.beginFrame(atTime: CACurrentMediaTime(), timeStamp: nil)
    renderer.addUpdate(renderer.bounds)
    renderer.render()
    renderer.endFrame()
    let buffer = try #require(queue.makeCommandBuffer())
    let blit = try #require(buffer.makeBlitCommandEncoder())
    blit.synchronize(resource: texture)
    blit.endEncoding()
    buffer.commit()
    buffer.waitUntilCompleted()
    var bgra = [UInt8](repeating: 0, count: w * h * 4)
    bgra.withUnsafeMutableBytes { raw in
        guard let base = raw.baseAddress else { return }
        texture.getBytes(base, bytesPerRow: w * 4, from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
    }
    root.sublayers = nil
    // The renderer's texture starts at Core Animation's origin, the bottom: row 0 of the raster is the top.
    var rgba = [UInt8](repeating: 0, count: bgra.count)
    for y in 0..<h {
        for x in 0..<w {
            let from = ((h - 1 - y) * w + x) * 4, to = (y * w + x) * 4
            rgba[to] = bgra[from + 2]; rgba[to + 1] = bgra[from + 1]; rgba[to + 2] = bgra[from]; rgba[to + 3] = bgra[from + 3]
        }
    }
    return Raster(width: w, height: h, rgba: rgba)
}

/// Writes `raster` as a PNG (development snapshots, `CRANNY_SNAPSHOT_DIR`).
func writePNG(_ raster: Raster, to url: URL) throws {
    var data = raster.rgba
    let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
    let image: CGImage? = data.withUnsafeMutableBytes { buffer in
        CGContext(data: buffer.baseAddress, width: raster.width, height: raster.height, bitsPerComponent: 8,
                  bytesPerRow: raster.width * 4, space: space,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage()
    }
    let rep = NSBitmapImageRep(cgImage: try #require(image))
    try #require(rep.representation(using: .png, properties: [:])).write(to: url)
}
