// CrannyQuickApps/QuickAppsSettings.swift — the module's settings keys (ARCHITECTURE.md §10.4, §3.11).
import CrannyCore
import Foundation

/// Settings of Quick Apps & Shortcuts, namespace `quickapps` (reset by Settings ▸ Shortcuts ▸ "Reset…").
/// Never rename a key or change its type: add a new key and migrate in `onLaunch`.
public enum QuickAppsSettings {
    /// The quick apps, by bundle identifier (default Finder, Safari, Mail, Music). Apps that are not installed
    /// are hidden from the launcher and marked in Settings, never dropped.
    public static let apps = SettingKey<[AppEntry]>(.quickApps, "apps", default: AppEntry.defaults)
    /// Shortcuts.app shortcuts on the launcher.
    public static let shortcuts = SettingKey<[ShortcutEntry]>(.quickApps, "shortcuts", default: [])
    /// Names under the tiles.
    public static let showsLabels = SettingKey<Bool>(.quickApps, "showsLabels", default: false)
    /// The tile order across apps and shortcuts, as tile ids ("app:<bundle id>", "shortcut:<identifier>"),
    /// written when the user reorders tiles. Empty = apps first, then shortcuts; ids of removed tiles are ignored
    /// and tiles missing from it follow in list order (`LauncherOrder`).
    public static let order = SettingKey<[String]>(.quickApps, "order", default: [])
}
