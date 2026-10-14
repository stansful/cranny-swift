// CrannyOnboarding/Model/OpenMethod.swift — step 2's three ways in, and how a real `NotchEvent` maps onto
// them (pure). DESIGN.md §12.1: "Detects the actual opening of the real notch: ✓ per method".
import CrannyCore
import Foundation

/// One way to open Cranny, as offered by the cards of step 2.
nonisolated enum OpenMethod: String, CaseIterable, Sendable {
    case hover, click, shortcut

    /// The method behind a real opening; nil for openings the person did not make that way (code, drags…).
    init?(_ reason: OpenReason) {
        switch reason {
        case .hover: self = .hover
        case .click: self = .click
        case .keyboard: self = .shortcut
        case .swipe, .drag, .activity, .programmatic, .tutorial: return nil
        }
    }

    /// The `CoreSettings.openMode` this card selects.
    var mode: OpenMode {
        switch self {
        case .hover: .hover
        case .click: .click
        case .shortcut: .shortcutOnly
        }
    }

    init(mode: OpenMode) {
        switch mode {
        case .hover: self = .hover
        case .click: self = .click
        case .shortcutOnly: self = .shortcut
        }
    }

    /// The method a real event proves, if any.
    static func detected(by event: NotchEvent) -> OpenMethod? {
        guard case .opened(let reason) = event else { return nil }
        return OpenMethod(reason)
    }
}
