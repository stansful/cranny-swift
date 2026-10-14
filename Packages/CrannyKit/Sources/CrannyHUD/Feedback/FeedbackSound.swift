// CrannyHUD/Feedback/FeedbackSound.swift — the "Play feedback when volume is changed" sound (DESIGN.md §10,
// §14.3; ARCHITECTURE.md §7.1). macOS plays it itself only for keys it handles; a consumed key is silent, so
// Cranny replays the system's own file when a consumed volume key goes up. Cranny ships no audio.
//
// The global default `com.apple.sound.beep.feedback` (1 = on) is read, never written; ⇧ inverts it (Apple's
// convention, [UNVERIFIED] R3 §1.5). Muted in Demo mode and while the output is muted.
import AppKit
import CrannyCore
import Foundation
import os

private let log = Log.logger(.hud)

@MainActor final class FeedbackSound {
    /// The system's volume feedback sound (exists on macOS 27.0.1 [VERIFIED R3]).
    static let systemSoundPath = "/System/Library/LoginPlugins/BezelServices.loginPlugin/Contents/Resources/volume.aiff"
    /// The global default behind System Settings ▸ Sound ▸ "Play feedback when volume is changed".
    static let feedbackDefaultsKey = "com.apple.sound.beep.feedback"

    private let isEnabledInSystem: @MainActor () -> Bool
    private var sound: NSSound?
    private var loadFailed = false

    /// `isEnabledInSystem` reads the global default (injected in tests).
    init(isEnabledInSystem: @escaping @MainActor () -> Bool = { FeedbackSound.systemFeedbackEnabled() }) {
        self.isEnabledInSystem = isEnabledInSystem
    }

    /// Pure rule: the system setting, inverted by ⇧, never in Demo mode or while muted.
    nonisolated static func shouldPlay(systemFeedback: Bool, shiftHeld: Bool, demoMode: Bool, muted: Bool) -> Bool {
        !demoMode && !muted && (systemFeedback != shiftHeld)
    }

    /// `UserDefaults.standard` searches the global domain, where System Settings stores the switch.
    static func systemFeedbackEnabled(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.integer(forKey: feedbackDefaultsKey) == 1
    }

    /// Called when a consumed volume key goes up.
    func keyReleased(shiftHeld: Bool, demoMode: Bool, muted: Bool) {
        guard Self.shouldPlay(systemFeedback: isEnabledInSystem(), shiftHeld: shiftHeld, demoMode: demoMode, muted: muted),
              let sound = loadedSound() else { return }
        sound.stop()
        sound.play()
    }

    private func loadedSound() -> NSSound? {
        if let sound { return sound }
        guard !loadFailed else { return nil }
        guard let loaded = NSSound(contentsOfFile: Self.systemSoundPath, byReference: true) else {
            loadFailed = true
            log.info("volume feedback sound not found; feedback stays silent")
            return nil
        }
        sound = loaded
        return loaded
    }
}
