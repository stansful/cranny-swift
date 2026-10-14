// CrannyAppShell/Overlay/FullScreenDetector.swift — "is a full-screen app in front on this display?" (ARCHITECTURE.md
// §5.7, R1 §3.4, R3 §10). There is no public API, so: a layer-0 window of another app covers the display (its height
// may be short by the notch band) AND (its owner is frontmost OR the Window Server's layer-24 menu-bar window is gone
// from that display). Window bounds, layers and owner PIDs need no Screen Recording permission (only titles do).
// `evaluate` is pure; `snapshot()` is the one window-server query, run 0.6 s after space/app changes and lazily
// before a hover-open, never on a timer. It keeps only what the heuristic reads: windows of layer 0 and of the
// menu-bar layer, each read from the window server's own dictionary (no Swift copy of every window), the owner's name
// only for the menu-bar layer.
import AppKit
import CoreGraphics
import Foundation

nonisolated enum FullScreenDetector {
    /// One on-screen window, as `CGWindowListCopyWindowInfo` reports it (CG coordinates: top-left origin).
    struct Window: Equatable, Sendable {
        var layer: Int
        var bounds: CGRect
        var ownerPID: pid_t
        var ownerName: String
    }

    /// One display in CG coordinates, with the notch band height (0 without a notch).
    struct Display: Equatable, Sendable {
        var id: CGDirectDisplayID
        var bounds: CGRect
        var notchBand: CGFloat
    }

    /// What is in front of one display.
    struct Front: Equatable, Sendable {
        var fullScreen = false
        /// The frontmost app is excluded (`CoreSettings.excludedBundleIDs`) and has a window on this display.
        var excludedApp = false
    }

    /// The menu-bar window layer (`kCGMainMenuWindowLevelKey`, 24 on macOS 27, R1 §3.2).
    static let menuBarLayer = Int(CGWindowLevelForKey(.mainMenuWindow))

    /// Pure heuristic over a window list. `ignoredPIDs`: Cranny itself and the Dock.
    static func evaluate(windows: [Window], displays: [Display], frontmostPID: pid_t?, frontmostIsExcluded: Bool,
                         ignoredPIDs: Set<pid_t>) -> [CGDirectDisplayID: Front] {
        var result: [CGDirectDisplayID: Front] = [:]
        for display in displays {
            let menuBarPresent = windows.contains { isMenuBar($0, of: display.bounds) }
            let fullScreen = windows.contains { window in
                guard window.layer == 0, !ignoredPIDs.contains(window.ownerPID) else { return false }
                switch coverage(window.bounds, display) {
                case .exact?: return window.ownerPID == frontmostPID || !menuBarPresent
                // A zoomed window on a notched display has the same frame: only a missing menu bar tells them apart.
                case .belowBand?: return !menuBarPresent
                case nil: return false
                }
            }
            let excluded = frontmostIsExcluded && windows.contains { window in
                window.layer == 0 && window.ownerPID == frontmostPID && window.bounds.intersects(display.bounds)
            }
            result[display.id] = Front(fullScreen: fullScreen, excludedApp: excluded)
        }
        return result
    }

    /// How a window covers a display.
    enum Coverage: Equatable, Sendable {
        /// Exactly the display's bounds.
        case exact
        /// Everything below the notch band: full-screen apps that stay out of the camera housing (R1 §3.4).
        case belowBand
    }

    static func coverage(_ bounds: CGRect, _ display: Display) -> Coverage? {
        let d = display.bounds
        guard abs(bounds.minX - d.minX) < 1, abs(bounds.width - d.width) < 1, abs(bounds.maxY - d.maxY) < 1 else { return nil }
        if abs(bounds.minY - d.minY) < 1 { return .exact }
        if display.notchBand > 0, abs(bounds.minY - (d.minY + display.notchBand)) < 1 { return .belowBand }
        return nil
    }

    // MARK: Window server

    /// On-screen windows of layer 0 and of the menu-bar layer, desktop elements excluded (one call, ≈ 1–3 ms; no
    /// permission needed). Status items, menus, the Dock and the rest are skipped by their layer before anything
    /// else of them is read.
    static func snapshot() -> [Window] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as NSArray? else { return [] }
        var windows: [Window] = []
        for case let info as NSDictionary in list {
            guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0 || layer == menuBarLayer else { continue }
            if let window = window(from: info, layer: layer) { windows.append(window) }
        }
        return windows
    }

    /// What `snapshot()` keeps of one window-server entry, whatever its layer.
    static func window(from info: [String: Any]) -> Window? {
        guard let layer = info[kCGWindowLayer as String] as? Int else { return nil }
        return window(from: info as NSDictionary, layer: layer)
    }

    /// One window of `layer`: the owner's name only where `isMenuBar` reads it (empty for every other layer).
    private static func window(from info: NSDictionary, layer: Int) -> Window? {
        guard let pid = info[kCGWindowOwnerPID as String] as? Int,
              let boundsDictionary = info[kCGWindowBounds as String] as? NSDictionary,
              let bounds = CGRect(dictionaryRepresentation: boundsDictionary as CFDictionary) else { return nil }
        let ownerName = layer == menuBarLayer ? info[kCGWindowOwnerName as String] as? String ?? "" : ""
        return Window(layer: layer, bounds: bounds, ownerPID: pid_t(pid), ownerName: ownerName)
    }

    /// Height of the Window Server's menu-bar window on a display (CG bounds), for auto-hidden menu bars (§5.4).
    static func menuBarHeight(on displayBounds: CGRect, windows: [Window]) -> CGFloat? {
        windows.first { isMenuBar($0, of: displayBounds) }.map(\.bounds.height).flatMap { $0 > 0 ? $0 : nil }
    }

    /// The Window Server's layer-24 menu-bar window of THIS display: same top-left corner and width. Two displays
    /// side by side with aligned tops and equal widths differ only in x, so both coordinates are compared.
    static func isMenuBar(_ window: Window, of displayBounds: CGRect) -> Bool {
        window.layer == menuBarLayer && window.ownerName == "Window Server"
            && abs(window.bounds.minX - displayBounds.minX) < 1 && abs(window.bounds.minY - displayBounds.minY) < 1
            && abs(window.bounds.width - displayBounds.width) < 1
    }
}
