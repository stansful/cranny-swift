// CrannyTodos/Model/TodoFeedback.swift — what a completed to-do feels and sounds like (DESIGN.md §14.2–§14.3):
// a `.generic` haptic (honours Gestures ▸ Haptic feedback through `Haptics`) and, only with General ▸ UI sounds
// on and Demo mode off, the system sound "Tink" played by name (Cranny ships no audio files).
import AppKit
import CrannyCore

struct TodoFeedback {
    /// The system sound for a completed to-do.
    static let completionSound = "Tink"

    let haptic: @MainActor () -> Void
    let sound: @MainActor (String) -> Void

    static func live(haptics: Haptics) -> TodoFeedback {
        TodoFeedback(haptic: { haptics.play(.generic) }, sound: { NSSound(named: $0)?.play() })
    }

    /// Previews and tests: no haptics, no sounds.
    static let silent = TodoFeedback(haptic: {}, sound: { _ in })

    /// "Tink" plays only when the user turned UI sounds on, and never in Demo mode (DESIGN.md §14.3).
    static func playsSound(uiSounds: Bool, isDemoMode: Bool) -> Bool { uiSounds && !isDemoMode }
}
