// CrannyOnboarding/Model/OpenPrompt.swift — how to tell the person to open Cranny the way they chose in step 2
// (`CoreSettings.openMode`) with the Open Cranny binding they have. Shared by step 2's coach mark ("here", under
// the real notch) and the tour's first step ("the notch"), so the tour never asks for a hover that does nothing
// in Click or Shortcut-only mode (only Hover opens on a dwell). A click opens Cranny in every mode.
import CrannyCore
import Foundation

nonisolated enum OpenPrompt: Equatable, Sendable {
    /// Hover: rest the pointer on the notch (or press the shortcut).
    case rest(orPress: Bool)
    /// Click: click the notch (or press the shortcut).
    case click(orPress: Bool)
    /// Shortcut only: press the shortcut.
    case press
    /// Shortcut only, but Open Cranny has no shortcut.
    case noShortcut

    init(_ method: OpenMethod, hasShortcut: Bool) {
        switch method {
        case .hover: self = .rest(orPress: hasShortcut)
        case .click: self = .click(orPress: hasShortcut)
        case .shortcut: self = hasShortcut ? .press : .noShortcut
        }
    }

    /// The sentence ends with the shortcut's key cap.
    var endsWithKeyCap: Bool {
        switch self {
        case .rest(let orPress), .click(let orPress): orPress
        case .press: true
        case .noShortcut: false
        }
    }

    /// Step 2's coach mark under the real notch (DESIGN.md §12.1: "Rest the pointer here, or press ⌃⌥N").
    var coachText: String {
        switch self {
        case .rest(true): String(localized: "Rest the pointer here, or press", bundle: .module, comment: "Welcome step 2: coach mark under the real notch; followed by a key cap such as ⌃⌥N")
        case .rest(false): String(localized: "Rest the pointer here", bundle: .module, comment: "Welcome step 2: coach mark under the real notch (no shortcut set)")
        case .click(true): String(localized: "Click here, or press", bundle: .module, comment: "Welcome step 2: coach mark under the real notch; followed by a key cap such as ⌃⌥N")
        case .click(false): String(localized: "Click here", bundle: .module, comment: "Welcome step 2: coach mark under the real notch (no shortcut set)")
        case .press: String(localized: "Press", bundle: .module, comment: "Welcome step 2: coach mark under the real notch; followed by a key cap such as ⌃⌥N")
        case .noShortcut: String(localized: "Set a shortcut in Settings ▸ Keyboard", bundle: .module, comment: "Welcome step 2: coach mark when the Open Cranny shortcut is turned off")
        }
    }

    /// The tour's first step (DESIGN.md §12.2: "Rest the pointer on the notch, or press ⌃⌥N").
    var tutorialText: String {
        switch self {
        case .rest(true): String(localized: "Rest the pointer on the notch, or press", bundle: .module, comment: "Tutorial step 1; followed by a key cap such as ⌃⌥N")
        case .rest(false): String(localized: "Rest the pointer on the notch, or click it", bundle: .module, comment: "Tutorial step 1 (no keyboard shortcut set)")
        case .click(true): String(localized: "Click the notch, or press", bundle: .module, comment: "Tutorial step 1 when Cranny opens on a click; followed by a key cap such as ⌃⌥N")
        case .click(false), .noShortcut: String(localized: "Click the notch", bundle: .module, comment: "Tutorial step 1 when Cranny opens on a click, or has no shortcut to press")
        case .press: String(localized: "Press the shortcut", bundle: .module, comment: "Tutorial step 1 when Cranny opens only with its shortcut; followed by a key cap such as ⌃⌥N")
        }
    }

    /// The tour's glyph for the step.
    var tutorialSymbol: String {
        switch self {
        case .rest, .click, .noShortcut: "cursorarrow.motionlines"
        case .press: "keyboard"
        }
    }
}
