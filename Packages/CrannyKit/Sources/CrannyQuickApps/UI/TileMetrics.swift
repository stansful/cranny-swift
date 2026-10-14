// CrannyQuickApps/UI/TileMetrics.swift — sizes inside one launcher tile (DESIGN.md §7.3), derived from the grid
// cell so every density and text size keeps the Standard proportions (56-pt cell · 36-pt icon).
import CoreGraphics

/// The macOS icon grid: an app icon's visible squircle fills ≈ 80 % of its canvas (824 of 1024 px) with a corner
/// radius of ≈ 22.5 % of the squircle. Shortcut, "+" and "+N" squircles use the same body, so a row of app icons
/// and shortcuts reads as one set instead of the shortcuts looking a size larger.
nonisolated enum IconGrid {
    static func body(_ canvas: CGFloat) -> CGFloat { (canvas * 824 / 1024).rounded() }
    static func radius(_ body: CGFloat) -> CGFloat { body * 0.225 }
    /// SF Symbol / letter size on a squircle body (16 on the 29-pt body of a 36-pt icon).
    static func glyph(_ body: CGFloat) -> CGFloat { (body * 0.55).rounded() }
}

nonisolated struct TileMetrics: Equatable, Sendable {
    /// The tile = one grid cell.
    let tile: CGFloat
    let showsLabels: Bool

    /// Icon canvas: 36 at a 56-pt cell, 30 when a name sits under it.
    var icon: CGFloat { (tile * (showsLabels ? 30 : 36) / 56).rounded() }
    /// The squircle inside the canvas (shortcut, "+", "+N").
    var body: CGFloat { IconGrid.body(icon) }
    /// Space between the canvas edge and the squircle.
    var inset: CGFloat { (icon - body) / 2 }
    var squircleRadius: CGFloat { IconGrid.radius(body) }
    var glyph: CGFloat { IconGrid.glyph(body) }
    /// The Dock-style running dot.
    var dot: CGFloat { 4 }
    /// The running ring inside a squircle.
    var ring: CGFloat { (body * 0.55).rounded() }
    /// The failure badge on a squircle's corner.
    var badge: CGFloat { (icon * 0.36).rounded() }
    /// The edit-mode remove badge (its hit target is larger, see `RemoveBadge`).
    var removeBadge: CGFloat { (icon * 0.5).rounded() }
}
