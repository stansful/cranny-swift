// CrannyHUD/Keys/HUDTapConfig.swift — the immutable snapshot the key tap reads on every event
// (ARCHITECTURE.md §7.1). The main actor derives it from settings, the Accessibility grant and the environment
// and writes it into `HUDTapConfigBox`; the tap thread only reads it (an unfair lock, microseconds).
import CrannyCore
import os

nonisolated struct HUDTapConfig: Sendable, Equatable {
    /// "Replace the system HUD" is on, Accessibility is granted and the HUD activity is enabled. Without all
    /// three there is no tap and no HUD (D10: never two HUDs, never none).
    var isReplacing: Bool
    var handlesVolume: Bool
    var handlesBrightness: Bool
    var handlesKeyboardBacklight: Bool
    /// The shell can draw the HUD right now. False while the screen is locked or asleep, while a full-screen
    /// (or excluded) app is in front under "Hide everything", or while the display the HUD would appear on has no
    /// visible panel or has General ▸ Displays ▸ HUD off: the keys then go to macOS and its own HUD shows.
    var isPresentable: Bool

    /// Nothing is handled; the state before launch and after `stop()`.
    static let off = HUDTapConfig(isReplacing: false, handlesVolume: false, handlesBrightness: false,
                                  handlesKeyboardBacklight: false, isPresentable: false)

    /// Whether the event tap should exist at all (turning the setting off removes it). An existing tap receives
    /// events only while `isPresentable` (`KeyInterceptor.setEnabled`).
    var wantsTap: Bool { isReplacing && (handlesVolume || handlesBrightness || handlesKeyboardBacklight) }

    func handles(_ kind: HUDKind) -> Bool {
        switch kind {
        case .volume: handlesVolume
        case .brightness: handlesBrightness
        case .keyboardBacklight: handlesKeyboardBacklight
        }
    }

    /// Everything the snapshot depends on, read on the main actor.
    struct Inputs: Equatable, Sendable {
        var replaceSystemHUD: Bool
        var volume: Bool
        var brightness: Bool
        var keyboardBacklight: Bool
        /// Settings ▸ Live Activities toggle of the HUD activity: off means "let macOS show its HUD".
        var activityEnabled: Bool
        var accessibilityGranted: Bool
        var screenLocked: Bool
        var displaysAsleep: Bool
        var fullScreenInFront: Bool
        var fullScreenPolicy: FullScreenPolicy
        /// `SystemEnvironment.canPresentHUD`: the shell has a visible panel for the HUD on its display, and that
        /// display's General ▸ Displays ▸ HUD toggle is on.
        var shellCanPresentHUD: Bool
    }

    init(isReplacing: Bool, handlesVolume: Bool, handlesBrightness: Bool, handlesKeyboardBacklight: Bool,
         isPresentable: Bool) {
        self.isReplacing = isReplacing; self.handlesVolume = handlesVolume; self.handlesBrightness = handlesBrightness
        self.handlesKeyboardBacklight = handlesKeyboardBacklight; self.isPresentable = isPresentable
    }

    init(_ inputs: Inputs) {
        let replacing = inputs.replaceSystemHUD && inputs.accessibilityGranted && inputs.activityEnabled
        let hiddenByFullScreen = inputs.fullScreenInFront && inputs.fullScreenPolicy == .hideAll
        self.init(isReplacing: replacing,
                  handlesVolume: replacing && inputs.volume,
                  handlesBrightness: replacing && inputs.brightness,
                  handlesKeyboardBacklight: replacing && inputs.keyboardBacklight,
                  isPresentable: inputs.shellCanPresentHUD && !inputs.screenLocked && !inputs.displaysAsleep
                      && !hiddenByFullScreen)
    }
}

/// The one place the snapshot lives. Written by the main actor, read by the tap thread.
nonisolated final class HUDTapConfigBox: Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: HUDTapConfig.off)
    init() {}
    var current: HUDTapConfig { lock.withLock { $0 } }
    func update(_ config: HUDTapConfig) { lock.withLock { $0 = config } }
}
