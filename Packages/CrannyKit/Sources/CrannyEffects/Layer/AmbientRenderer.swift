// CrannyEffects/Layer/AmbientRenderer.swift — the render pipeline of the dedicated ambient Metal layer
// (ARCHITECTURE.md §10.1 open issue 1, design-owner decision): one full-screen triangle per frame through
// `ambientVertex` + the effect's fragment function, all from the module's `default.metallib`. The fragment
// functions call the same field code as the stitchable functions (Shaders/*.metal), so both paths match.
import CrannyCore
import Foundation
import Metal
import QuartzCore
import os

private let log = Log.logger(.effects)

@MainActor final class AmbientRenderer {
    /// One renderer per process; nil when Metal, the library or a pipeline is unavailable (logged once).
    static let shared: AmbientRenderer? = AmbientRenderer()

    /// 8-bit sRGB-encoded storage, like the SwiftUI layers the stitchable shaders draw into; the dither is
    /// sized for it (±0.5 LSB).
    static let pixelFormat = MTLPixelFormat.bgra8Unorm

    let device: any MTLDevice
    private let queue: any MTLCommandQueue
    private let library: any MTLLibrary
    private var pipelines: [AmbientEffect: any MTLRenderPipelineState] = [:]

    private init?() {
        guard ShaderEffects.isAvailable, let url = ShaderEffects.libraryURL,
              let device = MTLCreateSystemDefaultDevice() else { return nil }
        do {
            library = try device.makeLibrary(URL: url)
        } catch {
            log.error("Ambient layer: default.metallib does not load (\(error.localizedDescription, privacy: .public))")
            return nil
        }
        guard let queue = device.makeCommandQueue() else {
            log.error("Ambient layer: no command queue")
            return nil
        }
        queue.label = "Cranny ambient light"
        self.device = device
        self.queue = queue
    }

    /// The fragment function of each ambient effect.
    nonisolated static func fragmentName(_ effect: AmbientEffect) -> String {
        switch effect {
        case .aurora: "auroraFragment"
        case .motes: "motesFragment"
        case .tide: "tideFragment"
        case .halo: "haloFragment"
        }
    }

    /// The pipeline of `effect`, built on first use (a few milliseconds from the precompiled library).
    func pipeline(for effect: AmbientEffect) -> (any MTLRenderPipelineState)? {
        if let pipeline = pipelines[effect] { return pipeline }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = Self.fragmentName(effect)
        descriptor.vertexFunction = library.makeFunction(name: "ambientVertex")
        descriptor.fragmentFunction = library.makeFunction(name: Self.fragmentName(effect))
        descriptor.colorAttachments[0].pixelFormat = Self.pixelFormat
        do {
            let pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
            pipelines[effect] = pipeline
            return pipeline
        } catch {
            log.error("Ambient layer: no pipeline for \(effect.rawValue, privacy: .public) (\(error.localizedDescription, privacy: .public))")
            return nil
        }
    }

    // MARK: - Drawing

    /// Draws one frame into the layer's next drawable and presents it. Returns false when nothing was drawn.
    @discardableResult
    func draw(_ effect: AmbientEffect, uniforms: AmbientUniforms, in layer: CAMetalLayer) -> Bool {
        guard let pipeline = pipeline(for: effect), let drawable = layer.nextDrawable(),
              let buffer = queue.makeCommandBuffer() else { return false }
        guard encode(pipeline, uniforms: uniforms, target: drawable.texture, into: buffer) else { return false }
        buffer.present(drawable)
        buffer.commit()
        return true
    }

    /// Renders one frame offscreen and returns its BGRA bytes (premultiplied, row 0 = top). Tests compare it
    /// with the stitchable path; nothing in the app calls it.
    func image(_ effect: AmbientEffect, uniforms: AmbientUniforms, width: Int, height: Int) -> [UInt8]? {
        guard width > 0, height > 0, let pipeline = pipeline(for: effect) else { return nil }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: Self.pixelFormat, width: width,
                                                                  height: height, mipmapped: false)
        descriptor.usage = [.renderTarget]
        descriptor.storageMode = .managed
        guard let texture = device.makeTexture(descriptor: descriptor), let buffer = queue.makeCommandBuffer(),
              encode(pipeline, uniforms: uniforms, target: texture, into: buffer),
              let blit = buffer.makeBlitCommandEncoder() else { return nil }
        blit.synchronize(resource: texture)
        blit.endEncoding()
        buffer.commit()
        buffer.waitUntilCompleted()
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        bytes.withUnsafeMutableBytes { raw in
            guard let base = raw.baseAddress else { return }
            texture.getBytes(base, bytesPerRow: width * 4, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        }
        return bytes
    }

    private func encode(_ pipeline: any MTLRenderPipelineState, uniforms: AmbientUniforms,
                        target: any MTLTexture, into buffer: any MTLCommandBuffer) -> Bool {
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = buffer.makeRenderCommandEncoder(descriptor: pass) else { return false }
        encoder.setRenderPipelineState(pipeline)
        var values = uniforms
        encoder.setFragmentBytes(&values, length: MemoryLayout<AmbientUniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        return true
    }
}
