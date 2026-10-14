import Testing
import CrannyCore
@testable import CrannyEffects

@Test func budgetPausesWhenClosed() {
    let b = EffectBudget(isOpen: false, onScreen: true, lowPower: false, fullScreenFront: false, reduceMotion: false, onBattery: false)
    #expect(b.minimumInterval == nil)
}
