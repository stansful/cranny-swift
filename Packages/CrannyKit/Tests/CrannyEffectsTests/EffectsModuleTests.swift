import CrannyCore
import Foundation
import Metal
import SwiftUI
import Testing
@testable import CrannyEffects

@Test func budgetPausesWhenClosed() {
    let b = EffectBudget(isOpen: false, onScreen: true, lowPower: false, fullScreenFront: false, reduceMotion: false, onBattery: false)
    #expect(b.minimumInterval == nil)
}

@Test func shaderPathOnlyWhileMotionIsAllowed() {
    func budget(reduceMotion: Bool = false, lowPower: Bool = false, isOpen: Bool = true) -> EffectBudget {
        EffectBudget(isOpen: isOpen, onScreen: true, lowPower: lowPower, fullScreenFront: false, reduceMotion: reduceMotion, onBattery: false)
    }
    #expect(!ShaderEffects.usesShader(budget(reduceMotion: true)))          // Reduce Motion → frozen SwiftUI frame
    #expect(!ShaderEffects.usesShader(budget(lowPower: true)))              // Low Power / thermal → static halo
    #expect(ShaderEffects.usesShader(budget(isOpen: false)) == ShaderEffects.usesShader(budget()))   // pausing never flips paths
}

/// Every stitchable and layer function is required, so a missing one turns every effect onto its fallback
/// instead of rendering transparent.
@Test func requiredFunctionsCoverEveryEffect() {
    #expect(ShaderEffects.requiredFunctions == ShaderEffects.stitchableFunctions.union(ShaderEffects.layerFunctions))
    #expect(ShaderEffects.stitchableFunctions == ["crannyDither", "auroraField", "tideField", "motesField", "haloGlow",
                                                  "songRipple", "liquidNeck", "emberBurst", "chargeSweep"])
    for effect in AmbientEffect.allCases {
        #expect(ShaderEffects.layerFunctions.contains(AmbientRenderer.fragmentName(effect)))
    }
    #expect(ShaderEffects.layerFunctions.contains("ambientVertex"))
}

/// `requiredFunctions` lists exactly what ships: nothing missing, nothing unlisted.
@Test(.enabled(if: AmbientGPU.device() != nil)) func requiredFunctionsMatchTheLibrary() throws {
    let url = try #require(ShaderEffects.libraryURL)
    let device = try #require(AmbientGPU.device())
    let library = try device.makeLibrary(URL: url)
    #expect(Set(library.functionNames) == ShaderEffects.requiredFunctions)
}

/// Only the compiled library ships: SwiftPM's built-in rule compiles `Shaders/*.metal` into `default.metallib`
/// and must not copy the sources or `CrannyShaders.h` into the bundle (ARCHITECTURE.md §2.2, §8.8).
@Test func bundleShipsNoShaderSources() throws {
    let resources = try #require(Bundle.module.resourceURL)
    let files = (FileManager.default.enumerator(at: resources, includingPropertiesForKeys: nil)?.allObjects ?? [])
        .compactMap { ($0 as? URL)?.lastPathComponent }
    #expect(files.contains("default.metallib"))
    #expect(files.filter { $0.hasSuffix(".metal") || $0.hasSuffix(".h") }.isEmpty)
}

/// The QA launch arguments: `-CrannyDisableShaders YES` forces every fallback, `-CrannyDisableEffectLayer YES`
/// keeps the light in SwiftUI. Tested with a private defaults suite, never the app's.
@Test func qaSwitches() throws {
    let suite = "CrannyEffectsTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    #expect(ShaderEffects.allowsLayer(defaults: defaults))
    defaults.set(true, forKey: ShaderEffects.disableLayerKey)
    #expect(!ShaderEffects.allowsLayer(defaults: defaults))
    defaults.set(true, forKey: ShaderEffects.disableKey)
    #expect(ShaderEffects.unavailabilityReason(defaults: defaults) == "CrannyDisableShaders is set")
}

@Test func diagnosticsNameTheRenderer() {
    #expect(["metal-layer", "swiftui-shader", "fallback"].contains(EffectsDiagnostics.ambientRenderer))
    if EffectsDiagnostics.shaderStatus == "ok", ShaderEffects.allowsLayer {
        #expect(EffectsDiagnostics.ambientRenderer == "metal-layer")
    }
}

/// `ambientLightRendering(.inline)` (which `rasterize` applies around these public views, as a snapshot caller would)
/// keeps the light inside SwiftUI, so `ImageRenderer` captures it instead of an empty platform view.
@Test(.enabled(if: shadersRun)) func inlineRenderingReachesSnapshots() throws {
    let size = CGSize(width: 440, height: 130)
    let views: [AnyView] = [
        AnyView(AuroraField(palette: .afterglow, level: .vivid, energy: 0, budget: runningBudget)),
        AnyView(MotesField(palette: .afterglow, level: .vivid, energy: 0, budget: runningBudget)),
        AnyView(TideField(palette: .afterglow, level: .vivid, energy: 0, budget: runningBudget)),
    ]
    for view in views {
        #expect(try rasterize(view, size: size).peakAlpha > 0.2)
    }
}
