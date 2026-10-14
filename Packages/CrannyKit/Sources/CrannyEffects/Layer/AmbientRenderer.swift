// CrannyEffects/Layer/AmbientRenderer.swift — the render pipeline of the dedicated ambient Metal layer
// (ARCHITECTURE.md §10.1 open issue 1, design-owner decision): one full-screen triangle per frame through
// `ambientVertex` + the effect's fragment function, all from the module's `default.metallib`. The fragment
// functions call the same field code as the stitchable functions (Shaders/*.metal), so both paths match.
//
// Lifetime (ARCHITECTURE.md §9.2): one renderer per GPU, on the GPU `AmbientGPU` picks (never the discrete GPU of a
// Mac that also has an integrated one). Views hold it; between opens it stays alive only when holding it cannot keep
// a discrete GPU powered, otherwise it goes with the last view. Building one compiles every pipeline up front: if
// anything fails, no renderer exists, `AmbientLayerSupport` says so once, and the light uses the SwiftUI shader path.
import CoreGraphics
import CrannyCore
import Foundation
import Metal
import Observation
import QuartzCore
import os

private let log = Log.logger(.effects)

@MainActor final class AmbientRenderer {
    /// 8-bit sRGB-encoded storage, like the SwiftUI layers the stitchable shaders draw into; the dither is
    /// sized for it (±0.5 LSB).
    static let pixelFormat = MTLPixelFormat.bgra8Unorm

    let device: any MTLDevice
    private let queue: any MTLCommandQueue
    private let pipelines: [AmbientEffect: any MTLRenderPipelineState]

    /// Loads the library and builds the pipeline of every ambient effect on `device`; nil (logged) on any failure.
    init?(device: any MTLDevice) {
        guard ShaderEffects.isAvailable, let url = ShaderEffects.libraryURL else { return nil }
        do {
            let library = try device.makeLibrary(URL: url)
            var pipelines: [AmbientEffect: any MTLRenderPipelineState] = [:]
            for effect in AmbientEffect.allCases {
                let descriptor = MTLRenderPipelineDescriptor()
                descriptor.label = Self.fragmentName(effect)
                descriptor.vertexFunction = library.makeFunction(name: "ambientVertex")
                descriptor.fragmentFunction = library.makeFunction(name: Self.fragmentName(effect))
                descriptor.colorAttachments[0].pixelFormat = Self.pixelFormat
                pipelines[effect] = try device.makeRenderPipelineState(descriptor: descriptor)
            }
            self.pipelines = pipelines
        } catch {
            log.error("Ambient layer off on \(device.name, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
        guard let queue = device.makeCommandQueue() else {
            log.error("Ambient layer off on \(device.name, privacy: .public): no command queue")
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

    /// Pixels per point the layer renders `effect` at. The aurora and the halo are low-frequency light (their finest
    /// structure is ≈ 10 pt), so they render at 1 pixel per point and Core Animation scales them up: a quarter of the
    /// GPU work on Retina displays with no visible difference. Motes and tide lines need every pixel.
    nonisolated static func renderScale(for effect: AmbientEffect, displayScale: CGFloat) -> CGFloat {
        switch effect {
        case .aurora, .halo: min(displayScale, 1)
        case .motes, .tide: displayScale
        }
    }

    // MARK: - Sharing

    private final class WeakRenderer {
        weak var renderer: AmbientRenderer?
        init(_ renderer: AmbientRenderer) { self.renderer = renderer }
    }

    /// Renderers in use, by GPU registry ID (views keep them alive).
    private static var inUse: [UInt64: WeakRenderer] = [:]
    /// Kept between opens: only a renderer whose GPU cannot be a discrete one held awake for nothing.
    private static var kept: AmbientRenderer?

    /// The renderer for the panel on `displayID` (nil: the main display), shared by every view on the same GPU.
    /// nil when no renderer can be built here; `AmbientLayerSupport` then turns the layer path off for good.
    static func renderer(forDisplay displayID: CGDirectDisplayID?) -> AmbientRenderer? {
        guard let device = AmbientGPU.device(forDisplay: displayID) else {
            AmbientLayerSupport.shared.layerFailed(reason: "no Metal device")
            return nil
        }
        if let renderer = inUse[device.registryID]?.renderer { return renderer }
        guard let renderer = AmbientRenderer(device: device) else {
            AmbientLayerSupport.shared.layerFailed(reason: "the pipelines do not build on \(device.name)")
            return nil
        }
        inUse = inUse.filter { $0.value.renderer != nil }
        inUse[device.registryID] = WeakRenderer(renderer)
        if !AmbientGPU.mayPinDiscreteGPU(AmbientGPU.Candidate(device), deviceCount: AmbientGPU.deviceCount) {
            kept = renderer
        }
        return renderer
    }

    // MARK: - Drawing

    /// Draws one frame into the layer's next drawable and presents it. `synchronized` presents it inside the current
    /// Core Animation transaction (a resize: the new frame appears together with the new bounds, never stretched);
    /// otherwise it is presented as soon as the GPU is done. Returns false when nothing was drawn.
    @discardableResult
    func draw(_ effect: AmbientEffect, uniforms: AmbientUniforms, in layer: CAMetalLayer, synchronized: Bool = false) -> Bool {
        guard let pipeline = pipelines[effect] else { return false }
        layer.presentsWithTransaction = synchronized
        guard let drawable = layer.nextDrawable(), let buffer = queue.makeCommandBuffer(),
              encode(pipeline, uniforms: uniforms, target: drawable.texture, into: buffer) else { return false }
        if synchronized {
            buffer.commit()
            buffer.waitUntilScheduled()
            drawable.present()
        } else {
            buffer.present(drawable)
            buffer.commit()
        }
        return true
    }

    /// Renders one frame offscreen and returns its BGRA bytes (premultiplied, row 0 = top). Tests compare it
    /// with the stitchable path; nothing in the app calls it.
    func image(_ effect: AmbientEffect, uniforms: AmbientUniforms, width: Int, height: Int) -> [UInt8]? {
        guard width > 0, height > 0, let pipeline = pipelines[effect] else { return nil }
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

    /// GPU seconds of one frame rendered offscreen at `width` × `height` pixels (the frame-time budget test).
    func gpuTime(_ effect: AmbientEffect, uniforms: AmbientUniforms, width: Int, height: Int) -> Double? {
        guard width > 0, height > 0, let pipeline = pipelines[effect] else { return nil }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: Self.pixelFormat, width: width,
                                                                  height: height, mipmapped: false)
        descriptor.usage = [.renderTarget]
        descriptor.storageMode = .private
        guard let texture = device.makeTexture(descriptor: descriptor), let buffer = queue.makeCommandBuffer(),
              encode(pipeline, uniforms: uniforms, target: texture, into: buffer) else { return nil }
        buffer.commit()
        buffer.waitUntilCompleted()
        return buffer.gpuEndTime - buffer.gpuStartTime
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

/// Whether the ambient light may use the dedicated Metal layer. It turns false (once, logged once) when no renderer
/// can be built on this Mac; views observe it and redraw the light on the SwiftUI shader path instead of leaving it
/// transparent (DESIGN.md §5.6 rule 2).
@Observable @MainActor final class AmbientLayerSupport {
    static let shared = AmbientLayerSupport()

    private(set) var isUsable = true

    func layerFailed(reason: String) {
        guard isUsable else { return }
        isUsable = false
        log.error("Ambient layer off (\(reason, privacy: .public)); drawing the light with the SwiftUI shaders")
    }
}
