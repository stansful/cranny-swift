import CrannyCore
import Testing
@testable import CrannyEffects

private func budget(isOpen: Bool = true, onScreen: Bool = true, lowPower: Bool = false, fullScreen: Bool = false,
                    reduceMotion: Bool = false, onBattery: Bool = false) -> EffectBudget {
    EffectBudget(isOpen: isOpen, onScreen: onScreen, lowPower: lowPower, fullScreenFront: fullScreen,
                 reduceMotion: reduceMotion, onBattery: onBattery)
}

@Test func ambientPathFollowsMotionPowerAndAvailability() {
    #expect(AmbientPath.resolve(budget: budget(), shadersAvailable: true, layerAllowed: true) == .layer)
    #expect(AmbientPath.resolve(budget: budget(), shadersAvailable: true, layerAllowed: false) == .shader)
    #expect(AmbientPath.resolve(budget: budget(), shadersAvailable: false, layerAllowed: true) == .fallback)
    #expect(AmbientPath.resolve(budget: budget(reduceMotion: true), shadersAvailable: true, layerAllowed: true) == .fallback)
    #expect(AmbientPath.resolve(budget: budget(lowPower: true), shadersAvailable: true, layerAllowed: true) == .staticHalo)
    #expect(AmbientPath.resolve(budget: budget(lowPower: true, reduceMotion: true), shadersAvailable: false,
                                layerAllowed: false) == .staticHalo)
    #expect(AmbientPath.layer.isShader && AmbientPath.shader.isShader)
    #expect(!AmbientPath.fallback.isShader && !AmbientPath.staticHalo.isShader)
}

/// Closing, occlusion, full screen and battery only pause or slow time; they never switch paths (nothing jumps).
@Test func pausingNeverSwitchesPaths() {
    for available in [true, false] {
        for layer in [true, false] {
            let running = AmbientPath.resolve(budget: budget(), shadersAvailable: available, layerAllowed: layer)
            for paused in [budget(isOpen: false), budget(onScreen: false), budget(fullScreen: true), budget(onBattery: true)] {
                #expect(AmbientPath.resolve(budget: paused, shadersAvailable: available, layerAllowed: layer) == running)
            }
        }
    }
}

@Test func momentPathFollowsMotionPowerAndAvailability() {
    #expect(MomentPath.resolve(budget: budget(), shadersAvailable: true) == .shader)
    #expect(MomentPath.resolve(budget: budget(isOpen: false), shadersAvailable: true) == .shader)   // moments play closed too
    #expect(MomentPath.resolve(budget: budget(), shadersAvailable: false) == .fallback)
    #expect(MomentPath.resolve(budget: budget(lowPower: true), shadersAvailable: true) == .fallback)
    #expect(MomentPath.resolve(budget: budget(reduceMotion: true), shadersAvailable: true) == .reduced)
    #expect(MomentPath.resolve(budget: budget(reduceMotion: true, onBattery: true), shadersAvailable: false) == .reduced)
}

@Test func budgetFrameRates() {
    #expect(budget().minimumInterval == 1.0 / 30)
    #expect(budget(onBattery: true).minimumInterval == 1.0 / 20)
    for paused in [budget(isOpen: false), budget(onScreen: false), budget(fullScreen: true), budget(reduceMotion: true),
                   budget(lowPower: true)] {
        #expect(paused.minimumInterval == nil)
    }
    #expect(budget(lowPower: true).effective(.aurora) == .halo)
    #expect(budget().effective(.tide) == .tide)
}

@Test func qaSwitchOnlyForcesOnScreen() {
    let paused = budget(onScreen: false)
    let adjusted = EffectsQA.adjusted(paused)
    #expect(adjusted.isOpen == paused.isOpen && adjusted.reduceMotion == paused.reduceMotion
            && adjusted.fullScreenFront == paused.fullScreenFront && adjusted.onBattery == paused.onBattery)
    #expect(adjusted.onScreen == (EffectsQA.keepsRunning || paused.onScreen))
    let lowPower = budget(lowPower: true)
    #expect(EffectsQA.adjusted(lowPower).lowPower == !EffectsQA.keepsRunning)
}
