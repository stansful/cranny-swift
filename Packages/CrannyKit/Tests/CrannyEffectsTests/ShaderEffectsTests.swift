import Foundation
import Metal
import Testing
@testable import CrannyEffects

@Test func metallibIsBundled() {
    #expect(Bundle.module.url(forResource: "default", withExtension: "metallib") != nil)
}

@Test(.enabled(if: MTLCreateSystemDefaultDevice() != nil)) func everyRequiredShaderLoads() {
    #expect(ShaderEffects.unavailabilityReason() == nil)
    #expect(ShaderEffects.isAvailable)
}
