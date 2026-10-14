// CrannySettingsUI/Components/SettingsRowInfo.swift — one searchable row of a shell pane (DESIGN.md §11.3).
// The pane draws its label from `title` and the search index reads the same value, so what you can find is
// exactly what you see. `id` is stable ("general.hoverDelay") and doubles as the deep-link target
// ("general#hoverDelay", see `SettingsNavigator`).
import CrannyCore
import Foundation

/// A row a search result can point at: its pane, its localized label and extra localized search terms.
struct SettingsRowInfo: Identifiable, Hashable {
    /// "<pane>.<name>", e.g. "general.hoverDelay". Stable: deep links and scroll targets use it.
    let id: String
    let pane: SettingsPageID
    /// Localized label, exactly as the row shows it.
    let title: String
    /// Localized synonyms ("external monitor" for Show on). Never shown.
    let keywords: [String]

    init(_ pane: SettingsPageID, _ name: String, title: String, keywords: [String] = []) {
        self.id = "\(pane.rawValue).\(name)"
        self.pane = pane
        self.title = title
        self.keywords = keywords
    }
}

/// Layout constants of the Settings window (DESIGN.md §11). Settings is an ordinary window with system colours
/// and text styles (DESIGN.md §2.0); these are the few sizes the design fixes for it.
enum SettingsMetrics {
    /// Default and minimum window content sizes (§11.1).
    static let windowSize = CGSize(width: 860, height: 620)
    static let minimumWindowSize = CGSize(width: 780, height: 560)
    /// Sidebar width range and default (§11.1).
    static let sidebarWidth: (min: CGFloat, ideal: CGFloat, max: CGFloat) = (190, 210, 260)
    /// The sidebar icon: a 20 × 20 rounded square, radius 5, continuous (§11.1).
    static let sidebarIcon: CGFloat = 20
    static let sidebarIconRadius: CGFloat = 5
    static let sidebarGlyph: CGFloat = 11
    /// The preview stage band (§11.2).
    static let stageHeight: CGFloat = 176
    /// The open Nook is scaled to fit the stage, never below this (§11.2).
    static let stageMinimumScale: CGFloat = 0.75
    /// The changed-value dot before a label (§11.3).
    static let changedDot: CGFloat = 6
    /// Search highlight: the accent wash fades over 1 s (§11.3).
    static let highlightFade: Double = 1
    static let highlightOpacity: Double = 0.22
    /// Reset All offers Undo for 10 s (§11.3, ARCHITECTURE D14).
    static let undoWindow: Duration = .seconds(10)
}
