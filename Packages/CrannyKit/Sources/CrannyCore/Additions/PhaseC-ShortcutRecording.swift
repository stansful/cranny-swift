// CrannyCore/Additions/PhaseC-ShortcutRecording.swift — additive Core change (Phase C, C-SHELL-14): Settings ▸ Keyboard
// tells the shell while a shortcut recorder listens, so the shell pauses its global hot keys (a registered one would
// otherwise run its action instead of being recorded). Default: nothing to pause.
import Foundation

extension AppControl {
    /// Default: no global shortcuts to pause (previews, test doubles).
    public func setShortcutRecording(_ recording: Bool) {}
}
