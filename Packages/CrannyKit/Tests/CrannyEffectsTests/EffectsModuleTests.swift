import CrannyCore
import Foundation
import Metal
import Testing
@testable import CrannyEffects

@Test func budgetPausesWhenClosed() {
    let b = EffectBudget(isOpen: false, onScreen: true, lowPower: false, fullScreenFront: false, reduceMotion: false, onBattery: false)
    #expect(b.minimumInterval == nil)
}

/// The Metal pipeline: SwiftPM compiled `Shaders/*.metal` into `default.metallib` inside this module's bundle,
/// and every stitchable function the Swift side names is in it.
@Test func shaderLibraryShipsInTheModuleBundle() throws {
    let url = try #require(EffectShaders.libraryURL, "default.metallib missing: is the Metal Toolchain installed?")
    #expect(url.deletingLastPathComponent().path.contains("CrannyKit_CrannyEffects.bundle"))
    let data = try Data(contentsOf: url)
    #expect(data.prefix(4) == Data("MTLB".utf8))                                   // metallib magic
    for name in EffectShaders.allFunctions {
        #expect(data.range(of: Data(name.utf8)) != nil, "\(name) not in default.metallib")
    }
}

@Test func shaderFunctionsResolveOnThisMac() throws {
    guard let device = MTLCreateSystemDefaultDevice() else { return }              // headless CI without a GPU: file check above only
    let library = try device.makeDefaultLibrary(bundle: EffectShaders.bundle)
    for name in EffectShaders.allFunctions {
        #expect(library.functionNames.contains(name))
        #expect(library.makeFunction(name: name) != nil)
    }
    #expect(EffectShaders.isAvailable)
    #expect(EffectShaders.status.hasPrefix("ok"))
}
