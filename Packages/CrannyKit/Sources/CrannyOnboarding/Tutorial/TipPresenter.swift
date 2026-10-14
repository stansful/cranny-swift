// CrannyOnboarding/Tutorial/TipPresenter.swift — what the tutorial (and step 2's coach mark) shows under the
// real notch, and the seam that keeps windows out of tests: the app uses `TipPanelPresenter` (an NSPanel),
// tests use a recording stand-in.
import CoreGraphics
import CrannyCore
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

        /// The SF Symbol drawn for the mark; nil draws none.
        var symbolName: String? {
            switch self {
            case .none: nil
            case .symbol(let name): name
            case .done: "checkmark.circle.fill"
            }
        }

        /// The ✓ bounces once when a step becomes done, never when the next step's glyph replaces it and never
        /// under Reduce Motion (DESIGN.md §14.1: symbols animate only on a state change).
        static func bounces(from old: Mark, to new: Mark, reduceMotion: Bool) -> Bool {
            new == .done && old != .done && !reduceMotion
        }
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
    /// (`TipSurroundings.anchor`), drawn with the notch's resolved `theme`. Owners hide the bubble instead of
    /// showing it without an anchor.
    func show(_ content: TipContent, under anchor: CGRect, theme: CrannyTheme)
    func hide()
}
