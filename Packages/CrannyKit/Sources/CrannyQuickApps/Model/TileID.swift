// CrannyQuickApps/Model/TileID.swift — identity of a launcher tile, as persisted in `QuickAppsSettings.order`.
import Foundation

/// A tile: an app by bundle identifier or a shortcut by Shortcuts.app identifier.
/// Raw form "app:<bundle id>" / "shortcut:<identifier>" (stable, persisted: never change it).
nonisolated enum TileID: Hashable, Sendable, CustomStringConvertible {
    case app(String)
    case shortcut(String)

    private static let appPrefix = "app:"
    private static let shortcutPrefix = "shortcut:"

    var rawValue: String {
        switch self {
        case .app(let bundleID): Self.appPrefix + bundleID
        case .shortcut(let id): Self.shortcutPrefix + id
        }
    }

    init?(rawValue: String) {
        if rawValue.hasPrefix(Self.appPrefix), rawValue.count > Self.appPrefix.count {
            self = .app(String(rawValue.dropFirst(Self.appPrefix.count)))
        } else if rawValue.hasPrefix(Self.shortcutPrefix), rawValue.count > Self.shortcutPrefix.count {
            self = .shortcut(String(rawValue.dropFirst(Self.shortcutPrefix.count)))
        } else {
            return nil
        }
    }

    var description: String { rawValue }
}
