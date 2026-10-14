import CrannyCore
import Foundation
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
    #expect(ShaderEffects.requiredFunctions == ["crannyDither", "auroraField"])
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
