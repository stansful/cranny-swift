// CrannyNotchUI/NotchUITokens.swift — the few values NotchUI's own chrome needs that Core's token tables do not
// carry, named in one place instead of literals in the views (ARCHITECTURE.md §9.4): SF Symbol glyph styles
// (DESIGN.md §14.1 "semibold at 13 pt in the band; medium in the Nook") of the header, palette and card chrome.
// Shared glyph styles are Core's `CrannySymbolStyle`; the gulp's curves are Core's `CrannyMotion.Delight`.
import CrannyCore
import SwiftUI

/// Glyph styles of NotchUI's chrome.
enum NotchGlyph {
    /// In the band (header tabs, the tab menu, the layout editor's +): semibold 13 (DESIGN.md §14.1).
    case band
    /// The palette's search field: medium 13 (in the Nook).
    case field
    /// A palette result's icon, in a 16-pt box: medium 12 (DESIGN.md §6.4).
    case paletteRow
    /// The card's 20-pt ⋯ button: medium 11 (DESIGN.md §6.8).
    case overflow
    /// The layout editor's "–" badge (Reduce Motion): medium 10 in an 18-pt circle (DESIGN.md §6.6).
    case removeBadge
    /// A placeholder card's glyph: medium 20 (the size of `WidgetStateView`'s glyph).
    case placeholder

    var font: Font {
        switch self {
        case .band: .system(size: 13, weight: .semibold)
        case .field: .system(size: 13, weight: .medium)
        case .paletteRow: .system(size: 12, weight: .medium)
        case .overflow: .system(size: 11, weight: .medium)
        case .removeBadge: .system(size: 10, weight: .medium)
        case .placeholder: CrannySymbolStyle.widgetState.font()
        }
    }
}

extension View {
    /// `font(glyph.font)` for an SF Symbol of NotchUI's chrome.
    func notchGlyph(_ glyph: NotchGlyph) -> some View { font(glyph.font) }
}

/// The gulp's curves (DESIGN.md §5.5) are Core's (`CrannyMotion.Delight`), which holds only those. NotchUI plays
/// only the gulp itself, the one delight that is its own shape motion; CrannyEffects times the other moments and
/// their Calm / Reduce Motion variants. The gulp plays only when the owner allows a delight (never under Instant)
/// and not under Reduce Motion.
typealias DelightMotion = CrannyMotion.Delight
