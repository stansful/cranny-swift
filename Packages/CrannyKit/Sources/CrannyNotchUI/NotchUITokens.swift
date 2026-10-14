// CrannyNotchUI/NotchUITokens.swift — the few values NotchUI's own chrome needs that Core's token tables do not
// carry, named in one place instead of literals in the views (ARCHITECTURE.md §9.4): SF Symbol glyph styles
// (DESIGN.md §14.1 "semibold at 13 pt in the band; medium in the Nook") and the delight curves of DESIGN.md
// §5.5–§5.6. Core change request: move `DelightMotion` into `CrannyMotion` (and a glyph table into Typography)
// when Core next changes; until then this file is the single source for NotchUI.
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
        case .placeholder: .system(size: 20, weight: .medium)
        }
    }
}

extension View {
    /// `font(glyph.font)` for an SF Symbol of NotchUI's chrome.
    func notchGlyph(_ glyph: NotchGlyph) -> some View { font(glyph.font) }
}

/// Curves of the one-shot delights (DESIGN.md §5.5–§5.6). They play only when the owner allows a delight (never
/// under Instant), and the Reduce Motion variants use `fade`.
nonisolated enum DelightMotion {
    /// The song-change energy ripple: energy + 0.5 · (1 − t/lifetime)², decaying fast then slow.
    static func ripple(lifetime: Double) -> Animation { .timingCurve(0.33, 0.67, 0.67, 1, duration: lifetime) }
    /// First light: the light fills outward from the camera over the moment's lifetime.
    static func firstLight(lifetime: Double) -> Animation { .easeOut(duration: lifetime) }
    /// The gulp: the bottom edge rises 3 pt in 0.07 s …
    static let gulpSwallow = Animation.easeIn(duration: Gulp.swallow)
    /// … and lands back over the rest of the 0.25-s moment, without bounce (it shrinks toward the hardware).
    static let gulpRecover = Animation.spring(duration: Gulp.recover, bounce: 0)
    /// Reduce Motion variants (static ember glow, instant rim): colour only, fading out over the lifetime.
    static func fade(lifetime: Double) -> Animation { .easeIn(duration: lifetime) }
}
