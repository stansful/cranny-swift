// CrannyHUD/Model/HUDHardware.swift — every device the HUD touches, behind protocols so the controller can be
// tested with fakes (no test ever changes the real volume, brightness or backlight, or installs an event tap).
import Foundation

nonisolated struct HUDHardware: Sendable {
    var volume: any SystemVolume
    var brightness: any DisplayBrightness
    var keyboard: any KeyboardBacklight
    /// The session event tap for a handler (`MediaKeyInterceptor` in the app).
    var makeInterceptor: @Sendable (MediaKeyHandler) -> any KeyInterceptor
    /// The default-output listener (`VolumeObserver` in the app).
    var makeVolumeObserver: @Sendable () -> any VolumeObserving

    /// The real devices. Creating it touches nothing: private frameworks resolve on first use.
    static var live: HUDHardware {
        HUDHardware(volume: CoreAudioVolume(), brightness: DisplayServicesBrightness(), keyboard: CoreBrightnessKeyboard(),
                    makeInterceptor: { MediaKeyInterceptor(handler: $0) }, makeVolumeObserver: { VolumeObserver() })
    }
}
