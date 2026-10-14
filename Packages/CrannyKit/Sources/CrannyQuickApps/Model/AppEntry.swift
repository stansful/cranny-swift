// CrannyQuickApps/Model/AppEntry.swift — a persisted quick app (`QuickAppsSettings.apps`).
import Foundation

/// An app on the launcher. It is stored by bundle identifier, so it survives moves and updates; an app that
/// is not installed (any more) is hidden from the launcher but kept in the list (ARCHITECTURE.md §10.4).
public nonisolated struct AppEntry: Codable, Hashable, Sendable, Identifiable {
    /// `CFBundleIdentifier`, e.g. "com.apple.Safari".
    public var bundleID: String

    /// The bundle identifier.
    public var id: String { bundleID }

    /// An entry for the app with this bundle identifier.
    public init(bundleID: String) { self.bundleID = bundleID }

    /// The default launcher: Finder, Safari, Mail and Music.
    public static let defaults: [AppEntry] = ["com.apple.finder", "com.apple.Safari", "com.apple.mail", "com.apple.Music"]
        .map(AppEntry.init(bundleID:))
}
