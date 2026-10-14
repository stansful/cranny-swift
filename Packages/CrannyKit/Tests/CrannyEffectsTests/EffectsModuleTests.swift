import CrannyCore
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
