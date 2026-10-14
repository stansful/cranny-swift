import CoreGraphics
import CrannyCore
import Foundation
import Metal
import Testing
@testable import CrannyEffects

// Which GPU the effects use (ARCHITECTURE.md §9.2): never a discrete GPU when the Mac has an integrated one, the
// display's GPU otherwise, and a renderer that could pin a discrete GPU is let go with its last view.

private typealias GPU = AmbientGPU.Candidate

@Test func dualGPUMacsDrawOnTheIntegratedGPU() {
    let integrated = GPU(id: 1, isLowPower: true), discrete = GPU(id: 2, isLowPower: false)
    // Even while the discrete GPU drives the display (an external monitor), the light never adds work to it.
    #expect(AmbientGPU.choose([discrete, integrated], displayDevice: 2) == 1)
    #expect(AmbientGPU.choose([integrated, discrete], displayDevice: 1) == 0)
    #expect(AmbientGPU.choose([discrete, integrated], displayDevice: nil) == 1)
}

@Test func otherMacsDrawOnTheDisplaysGPU() {
    let appleSilicon = GPU(id: 7, isLowPower: false)
    #expect(AmbientGPU.choose([appleSilicon], displayDevice: 7) == 0)
    #expect(AmbientGPU.choose([appleSilicon], displayDevice: nil) == 0)
    // A Mac Pro with two discrete GPUs: the one driving the panel's display, so frames need no copy.
    let first = GPU(id: 1, isLowPower: false), second = GPU(id: 2, isLowPower: false)
    #expect(AmbientGPU.choose([first, second], displayDevice: 2) == 1)
    // A headless compute GPU or an eGPU is never preferred over a built-in one without a display hint.
    let headless = GPU(id: 3, isLowPower: false, isHeadless: true), external = GPU(id: 4, isLowPower: false, isRemovable: true)
    #expect(AmbientGPU.choose([headless, external, first], displayDevice: nil) == 2)
    // ...but an eGPU driving the panel's display is used, and a removable low-power GPU is not "integrated".
    #expect(AmbientGPU.choose([first, external], displayDevice: 4) == 1)
    #expect(AmbientGPU.choose([GPU(id: 5, isLowPower: true, isRemovable: true), first], displayDevice: 1) == 1)
    #expect(AmbientGPU.choose([], displayDevice: nil) == nil)
}

@Test func onlyADiscreteGPUAmongSeveralIsLetGo() {
    #expect(!AmbientGPU.mayPinDiscreteGPU(GPU(id: 1, isLowPower: true), deviceCount: 2))
    #expect(!AmbientGPU.mayPinDiscreteGPU(GPU(id: 1, isLowPower: false), deviceCount: 1))     // the Mac's only GPU
    #expect(AmbientGPU.mayPinDiscreteGPU(GPU(id: 2, isLowPower: false), deviceCount: 2))
}

@Test(.enabled(if: shadersRun)) func thisMacsDeviceFollowsThePolicy() throws {
    let device = try #require(AmbientGPU.device())
    let devices = MTLCopyAllDevices()
    let display = CGDirectDisplayCopyCurrentMetalDevice(CGMainDisplayID())?.registryID
    let index = try #require(AmbientGPU.choose(devices.map(GPU.init), displayDevice: display))
    #expect(device.registryID == devices[index].registryID)
}

/// Every pipeline is built up front (a failure means no renderer, so the light takes the SwiftUI shader path), and
/// views on the same GPU share one renderer.
@Test(.enabled(if: shadersRun)) func rendererBuildsEveryPipelineAndIsShared() throws {
    let device = try #require(AmbientGPU.device())
    let renderer = try #require(AmbientRenderer(device: device))
    for effect in AmbientEffect.allCases {
        let uniforms = AmbientUniforms(state: layerState(effect), size: CGSize(width: 8, height: 8), scale: 1, time: 1,
                                       date: Date())
        #expect(renderer.image(effect, uniforms: uniforms, width: 8, height: 8) != nil, "\(effect): no pipeline")
    }
    let shared = try #require(AmbientRenderer.renderer(forDisplay: nil))
    #expect(AmbientRenderer.renderer(forDisplay: nil) === shared)
    #expect(shared.device.registryID == device.registryID)
}

/// The renderer can be built off the main actor (`prewarm`, before the first open) and then serves the first view:
/// the same pipelines as a synchronous build, shared with every view on that GPU.
@Test(.enabled(if: shadersRun)) func rendererBuildsOffTheMainActor() async throws {
    let device = try #require(AmbientGPU.device())
    let parts = try #require(await Task.detached(priority: .utility) { AmbientRenderer.build(on: device) }.value)
    #expect(Set(parts.pipelines.keys) == Set(AmbientEffect.allCases))
    let renderer = AmbientRenderer(parts)
    for effect in AmbientEffect.allCases {
        let uniforms = AmbientUniforms(state: layerState(effect), size: CGSize(width: 8, height: 8), scale: 1, time: 1,
                                       date: Date())
        #expect(renderer.image(effect, uniforms: uniforms, width: 8, height: 8) != nil, "\(effect): no pipeline")
    }
    await AmbientRenderer.prewarm()
    await AmbientRenderer.prewarm()                                     // a no-op once a renderer exists
    let shared = try #require(AmbientRenderer.renderer(forDisplay: nil))
    #expect(AmbientRenderer.renderer(forDisplay: nil) === shared)
}

/// A renderer that cannot be built turns the layer path off once; the light then uses the SwiftUI shader path
/// (`AmbientPath.resolve(… layerAllowed: false) == .shader`) instead of staying transparent.
@Test func layerFailureFallsBackToTheShaderPath() {
    let support = AmbientLayerSupport()
    #expect(support.isUsable)
    support.layerFailed(reason: "test")
    support.layerFailed(reason: "test again")
    #expect(!support.isUsable)
    let running = EffectBudget(isOpen: true, onScreen: true, lowPower: false, fullScreenFront: false,
                               reduceMotion: false, onBattery: false)
    #expect(AmbientPath.resolve(budget: running, shadersAvailable: true, layerAllowed: support.isUsable) == .shader)
}
