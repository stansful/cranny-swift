// CrannyCore/Additions/WP14-DisplayVisibility.swift — additive Core change (WP14): whether Cranny appears on a display,
// decided in one place so the shell's panels (`OverlayCoordinator.panelScreens`) and the Settings preview stage
// cannot disagree (ARCHITECTURE §4.9, §10.15; DESIGN.md §3.7, §11.2).
import Foundation

extension DisplayPreferences {
    /// Whether Cranny appears on a display. An explicit per-display Off (General ▸ Displays) hides it on any display.
    /// Otherwise Appearance ▸ "On displays without a notch" (`CoreSettings.noNotchStyle`) applies only where there is
    /// no hardware notch: a notched display keeps Cranny when that style is Off.
    ///
    /// - Parameters:
    ///   - preferences: the display's entry in `CoreSettings.perDisplay` (nil = all defaults, style Automatic).
    ///   - noNotchStyle: `CoreSettings.noNotchStyle`.
    ///   - hasNotch: the display has a camera housing (`NSScreen.safeAreaInsets.top > 0`).
    public static func showsCranny(_ preferences: DisplayPreferences?, noNotchStyle: NoNotchStyle, hasNotch: Bool) -> Bool {
        if let style = preferences?.style { return style != .off }
        return hasNotch || noNotchStyle != .off
    }
}
