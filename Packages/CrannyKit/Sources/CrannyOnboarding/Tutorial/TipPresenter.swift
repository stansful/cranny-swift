// CrannyOnboarding/Tutorial/TipPresenter.swift — what the tutorial (and step 2's coach mark) shows under the
// real notch, and the seam that keeps windows out of tests: the app uses `TipPanelPresenter` (an NSPanel),
// tests use a recording stand-in.
import CoreGraphics
import Foundation

/// The content of one bubble (DESIGN.md §12.2): one sentence, an optional key cap, "2 of 5" and a button.
nonisolated struct TipContent: Equatable, Sendable {
    nonisolated enum Mark: Equatable, Sendable {
        /// No glyph (the coach mark).
        case none
        /// The step's glyph while waiting for the person.
        case symbol(String)
        /// The step was really done: ✓ with a bounce.
        case done
    }

    var text: String
    var keys: String?
    /// "2 of 5" (micro style); nil for the coach mark.
    var progress: String?
    var mark: Mark = .none
    /// "Skip tour" while running, "Done" at the end; nil makes the bubble click-through (coach mark).
    var actionTitle: String?

    var isInteractive: Bool { actionTitle != nil }
}

@MainActor protocol TipPresenter: AnyObject {
    /// Called when the bubble's button is pressed.
    var onAction: (@MainActor () -> Void)? { get set }
    /// Shows (or updates and moves) the bubble under `anchor`, the shape in AppKit screen coordinates
    /// (`NotchControl.shapeFrameOnScreen()`); nil = under the menu bar of the main display.
    func show(_ content: TipContent, under anchor: CGRect?)
    func hide()
}
