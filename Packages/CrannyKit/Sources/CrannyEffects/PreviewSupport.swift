// CrannyEffects/PreviewSupport.swift — sample budgets for the `#Preview`s of this module.
import CrannyCore

extension EffectBudget {
    /// Open, on screen, on AC: 30 fps.
    static let previewRunning = EffectBudget(isOpen: true, onScreen: true, lowPower: false, fullScreenFront: false,
                                             reduceMotion: false, onBattery: false)
    /// Reduce Motion: the fallback's resting frame, no clock.
    static let previewReduceMotion = EffectBudget(isOpen: true, onScreen: true, lowPower: false,
                                                  fullScreenFront: false, reduceMotion: true, onBattery: false)
    /// Low Power Mode: the static halo.
    static let previewLowPower = EffectBudget(isOpen: true, onScreen: true, lowPower: true, fullScreenFront: false,
                                              reduceMotion: false, onBattery: true)
}
