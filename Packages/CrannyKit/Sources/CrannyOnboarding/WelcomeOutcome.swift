// CrannyOnboarding/WelcomeOutcome.swift — the public vocabulary of the Welcome window (DESIGN.md §12.1):
// its six steps and how it ended. The shell's `WelcomeWindowController` acts on the outcome.
import Foundation

/// The six steps of the Welcome window, in order (DESIGN.md §12.1). The gesture step is shown only when a
/// trackpad is present.
public nonisolated enum WelcomeStep: String, CaseIterable, Sendable {
    /// 1 · "Look up. That's Cranny." The real notch says hi.
    case hello
    /// 2 · Hover, click or shortcut, detected on the real notch.
    case openIt
    /// 3 · A practice notch on the stage (trackpad only).
    case gestures
    /// 4 · A starting layout (`NookPreset`).
    case preset
    /// 5 · Permissions, only for the features of that layout.
    case permissions
    /// 6 · Launch at login, updates and a cheat sheet.
    case done
}

/// How the Welcome window ended.
public nonisolated enum WelcomeOutcome: Sendable, Equatable {
    /// "Done": setup is finished and the panel has been opened once.
    case done
    /// "Take the 1-minute tour": the owner starts the interactive tutorial.
    case tour
    /// "Skip setup" (Esc, then confirmed) or the window was closed early.
    case skipped
}
