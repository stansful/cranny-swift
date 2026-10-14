// CrannyEffects/Layer/AmbientRenderer.swift — the render pipeline of the dedicated ambient Metal layer
// (ARCHITECTURE.md §10.1 open issue 1, design-owner decision): one full-screen triangle per frame through
// `ambientVertex` + the effect's fragment function, all from the module's `default.metallib`. The fragment
// functions call the same field code as the stitchable functions (Shaders/*.metal), so both paths match.
//
// Lifetime (ARCHITECTURE.md §9.2): one renderer per GPU, on the GPU `AmbientGPU` picks (never the discrete GPU of a
// Mac that also has an integrated one). Views hold it; between opens it stays alive only when holding it cannot keep
// a discrete GPU powered, otherwise it goes with the last view. Building one compiles every pipeline up front: if
// anything fails, no renderer exists, `AmbientLayerSupport` says so once, and the light uses the SwiftUI shader path.
// `prewarm()` (through `EffectsPreparation`) builds it on a utility thread before the first open, so the open
// animation does not wait for the library and four pipeline compiles on the main thread; without it the first view
// builds it synchronously, as before.
//
// Per frame: the effect's pipeline, `AmbientUniforms` in `buffer(0)` and, for aurora and motes, the frame's table
// (`AmbientFrameTables`) in `buffer(1)`. A drawable of exactly the lit band is neither loaded nor cleared (the triangle
// overwrites every pixel); a larger one left by a resize is cleared and the shader is scissored to the band.
import CoreGraphics
import CrannyCore
import Foundation
import Metal
import Observation
import QuartzCore
import os

private nonisolated let log = Log.logger(.effects)

@MainActor final class AmbientRenderer {
    /// 8-bit sRGB-encoded storage, like the SwiftUI layers the stitchable shaders draw into; the dither is
    /// sized for it (±0.5 LSB).
    nonisolated static let pixelFormat = MTLPixelFormat.bgra8Unorm

    let device: any MTLDevice
    private let queue: any MTLCommandQueue
    private let pipelines: [AmbientEffect: any MTLRenderPipelineState]
    /// The per-frame tables, refilled in place (no allocation per frame).
    private var auroraTable: [SIMD4<Float>] = []
    private var moteTable: [SIMD4<Float>] = []

    /// What a renderer is made of; built off the main actor by `prewarm()`, or synchronously by `init?(device:)`.
    nonisolated struct Parts: Sendable {
        let device: any MTLDevice
        let queue: any MTLCommandQueue
        let pipelines: [AmbientEffect: any MTLRenderPipelineState]
    }

    /// Loads the library and builds the pipeline of every ambient effect on `device`; nil (logged) on any failure.
    convenience init?(device: any MTLDevice) {
        guard let parts = Self.build(on: device) else { return nil }
        self.init(parts)
    }

    /// A renderer of parts built elsewhere (`prewarm()` builds them off the main actor).
    init(_ parts: Parts) {
        device = parts.device
        queue = parts.queue
        pipelines = parts.pipelines
    }

    /// The library, one pipeline per ambient effect and a command queue on `device`, on any thread; nil (logged) on any
    /// failure.
    nonisolated static func build(on device: any MTLDevice) -> Parts? {
        guard ShaderEffects.isAvailable, let url = ShaderEffects.libraryURL else { return nil }
        let pipelines: [AmbientEffect: any MTLRenderPipelineState]
        do {
            let library = try device.makeLibrary(URL: url)
            let vertex = library.makeFunction(name: "ambientVertex")
            var built: [AmbientEffect: any MTLRenderPipelineState] = [:]
            for effect in AmbientEffect.allCases {
                let descriptor = MTLRenderPipelineDescriptor()
                descriptor.label = fragmentName(effect)
                descriptor.vertexFunction = vertex
                descriptor.fragmentFunction = library.makeFunction(name: fragmentName(effect))
                descriptor.colorAttachments[0].pixelFormat = pixelFormat
                built[effect] = try device.makeRenderPipelineState(descriptor: descriptor)
            }
            pipelines = built
        } catch {
            log.error("Ambient layer off on \(device.name, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
        guard let queue = device.makeCommandQueue() else {
            log.error("Ambient layer off on \(device.name, privacy: .public): no command queue")
            return nil
        }
        queue.label = "Cranny ambient light"
        return Parts(device: device, queue: queue, pipelines: pipelines)
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

    /// Whole points at the top of a light `height` points tall that `effect` leaves clear at any time, palette and
    /// ripple; the drawable covers only the band below (`AmbientDrawableLayout`). The shaders' early-outs: aurora and
    /// motes are clear down to 40 % of the height, the tide above `0.8 · h − 1.45 · (3 + 7 · energy) − 10`; each
    /// moved up by the ripple's reach (`Ripple.amplitude`) and a point of margin. The halo lights everything. `energy`
    /// counts as at least the ripple's pulse (1.5), so the drawable does not change with the music.
    nonisolated static func litTop(_ effect: AmbientEffect, height: CGFloat, energy: Double) -> CGFloat {
        let reach = Ripple.amplitude + 1
        let top: CGFloat
        switch effect {
        case .aurora, .motes: top = 0.40 * height - reach
        case .tide: top = 0.80 * height - 1.45 * (3 + 7 * CGFloat(max(energy, 1.5))) - 10 - reach
        case .halo: top = 0
        }
        return max(top.rounded(.down), 0)
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
        register(renderer)
        return renderer
    }

    /// Builds the renderer of the main display's GPU on a utility thread and keeps it, so the first open finds it
    /// ready. Only where it may be kept between opens (a GPU that cannot be a discrete one held awake: every Mac but
    /// those with several discrete GPUs); a no-op once a renderer exists. A failure is left to `renderer(forDisplay:)`,
    /// which tries again and turns the layer path off.
    static func prewarm() async {
        guard kept == nil, inUse.values.allSatisfy({ $0.renderer == nil }) else { return }
        let parts = await Task.detached(priority: .utility) { () -> Parts? in
            guard ShaderEffects.isAvailable, let device = AmbientGPU.device(forDisplay: nil),
                  !AmbientGPU.mayPinDiscreteGPU(AmbientGPU.Candidate(device), deviceCount: AmbientGPU.deviceCount)
            else { return nil }
            return build(on: device)
        }.value
        guard let parts, kept == nil, inUse[parts.device.registryID]?.renderer == nil else { return }
        register(AmbientRenderer(parts))
    }

    /// Shares `renderer` with every view on its GPU, and keeps it between opens unless that could pin a discrete GPU.
    private static func register(_ renderer: AmbientRenderer) {
        inUse = inUse.filter { $0.value.renderer != nil }
        inUse[renderer.device.registryID] = WeakRenderer(renderer)
        if !AmbientGPU.mayPinDiscreteGPU(AmbientGPU.Candidate(renderer.device), deviceCount: AmbientGPU.deviceCount) {
            kept = renderer
        }
    }

    // MARK: - Drawing

    /// Draws one frame into the layer's next drawable and presents it. `region` (nil: the whole drawable) is the part
    /// of a larger drawable the light fills (`AmbientDrawableLayout.region`); the rest is cleared. `synchronized`
    /// presents it inside the current Core Animation transaction (a resize: the new frame appears together with the new
    /// bounds, never stretched); otherwise it is presented as soon as the GPU is done. Returns false when nothing was
    /// drawn.
    @discardableResult
    func draw(_ effect: AmbientEffect, uniforms: AmbientUniforms, in layer: CAMetalLayer, region: CGSize? = nil,
              synchronized: Bool = false) -> Bool {
        guard pipelines[effect] != nil else { return false }
        layer.presentsWithTransaction = synchronized
        guard let drawable = layer.nextDrawable(), let buffer = queue.makeCommandBuffer(),
              encode(effect, uniforms: uniforms, target: drawable.texture, region: region, clears: false, into: buffer)
        else { return false }
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
        guard width > 0, height > 0, pipelines[effect] != nil else { return nil }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: Self.pixelFormat, width: width,
                                                                  height: height, mipmapped: false)
        descriptor.usage = [.renderTarget]
        descriptor.storageMode = .managed
        guard let texture = device.makeTexture(descriptor: descriptor), let buffer = queue.makeCommandBuffer(),
              encode(effect, uniforms: uniforms, target: texture, region: nil, clears: true, into: buffer),
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
        guard width > 0, height > 0, pipelines[effect] != nil else { return nil }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: Self.pixelFormat, width: width,
                                                                  height: height, mipmapped: false)
        descriptor.usage = [.renderTarget]
        descriptor.storageMode = .private
        guard let texture = device.makeTexture(descriptor: descriptor), let buffer = queue.makeCommandBuffer(),
              encode(effect, uniforms: uniforms, target: texture, region: nil, clears: true, into: buffer)
        else { return nil }
        buffer.commit()
        buffer.waitUntilCompleted()
        return buffer.gpuEndTime - buffer.gpuStartTime
    }

    /// One full-screen triangle of `effect` into `target`. Without a `region` the triangle overwrites every pixel and
    /// blending is off, so the target is neither loaded nor cleared first (`.dontCare`) unless `clears` asks for it (the
    /// offscreen images). With a `region` a scissor keeps the shader to it and the rest is cleared, so it stays clear.
    private func encode(_ effect: AmbientEffect, uniforms: AmbientUniforms, target: any MTLTexture, region: CGSize?,
                        clears: Bool, into buffer: any MTLCommandBuffer) -> Bool {
        guard let pipeline = pipelines[effect] else { return false }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = clears || region != nil ? .clear : .dontCare
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = buffer.makeRenderCommandEncoder(descriptor: pass) else { return false }
        encoder.setRenderPipelineState(pipeline)
        if let region {
            encoder.setScissorRect(MTLScissorRect(x: 0, y: 0, width: min(max(Int(region.width), 1), target.width),
                                                  height: min(max(Int(region.height), 1), target.height)))
        }
        var values = uniforms
        encoder.setFragmentBytes(&values, length: MemoryLayout<AmbientUniforms>.stride, index: 0)
        switch effect {
        case .aurora:
            AmbientFrameTables.auroraLab(uniforms, into: &auroraTable)
            setTable(auroraTable, on: encoder)
        case .motes:
            AmbientFrameTables.motes(uniforms, into: &moteTable)
            setTable(moteTable, on: encoder)
        case .tide, .halo:
            break
        }
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        return true
    }

    /// The frame's table as `buffer(1)` of the fragment function (copied by Metal; ≤ 1152 bytes, under the 4-KB limit).
    private func setTable(_ table: [SIMD4<Float>], on encoder: any MTLRenderCommandEncoder) {
        table.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { return }
            encoder.setFragmentBytes(base, length: bytes.count, index: 1)
        }
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
