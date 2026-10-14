// CrannyQuickApps/QuickAppsError.swift — what can go wrong when launching apps and running shortcuts, as
// localized one-liners (ARCHITECTURE.md §9.3). Raw CLI or NSError text is logged, never shown.
import Foundation

/// A failure the user can see: in a tile's failure badge tooltip, the Settings pane or a widget state.
nonisolated enum QuickAppsError: Error, LocalizedError, Equatable, Hashable, Sendable {
    /// `/usr/bin/shortcuts` could not be started.
    case shortcutsUnavailable
    /// `shortcuts list` failed.
    case listFailed
    /// `shortcuts run` exited with an error (the shortcut itself failed or was stopped by an action).
    case shortcutFailed
    /// The shortcut is no longer in Shortcuts (deleted since it was added).
    case shortcutNotFound
    /// The app is not installed any more.
    case appNotFound
    /// LaunchServices refused to open the app.
    case appLaunchFailed

    var errorDescription: String? {
        switch self {
        case .shortcutsUnavailable:
            String(localized: "Shortcuts isn’t available on this Mac.", bundle: .module,
                   comment: "Quick Apps: error when the Shortcuts command-line tool cannot be started")
        case .listFailed:
            String(localized: "Couldn’t read your shortcuts.", bundle: .module,
                   comment: "Quick Apps: error when the list of Shortcuts.app shortcuts cannot be read")
        case .shortcutFailed:
            String(localized: "The shortcut stopped with an error.", bundle: .module,
                   comment: "Quick Apps: failure badge tooltip after a shortcut run failed")
        case .shortcutNotFound:
            String(localized: "This shortcut is no longer in Shortcuts.", bundle: .module,
                   comment: "Quick Apps: failure badge tooltip when the shortcut was deleted in Shortcuts.app")
        case .appNotFound:
            String(localized: "This app is no longer installed.", bundle: .module,
                   comment: "Quick Apps: error when a quick app cannot be found")
        case .appLaunchFailed:
            String(localized: "The app couldn’t be opened.", bundle: .module,
                   comment: "Quick Apps: error when macOS refuses to open a quick app")
        }
    }
}
