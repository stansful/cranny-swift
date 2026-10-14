// CrannyQuickApps/Model/LauncherTile.swift — one visible tile: an installed app or a shortcut.
import Foundation

nonisolated enum LauncherTile: Identifiable, Hashable, Sendable {
    case app(ResolvedApp)
    case shortcut(ShortcutEntry)

    var id: TileID {
        switch self {
        case .app(let app): .app(app.bundleID)
        case .shortcut(let entry): .shortcut(entry.id)
        }
    }

    /// App display name, or the shortcut's name (with a fallback for an unnamed shortcut).
    var name: String {
        switch self {
        case .app(let app): app.name
        case .shortcut(let entry): entry.displayName
        }
    }
}

extension ShortcutEntry {
    /// The name, or "Untitled shortcut" for a shortcut without one.
    nonisolated var displayName: String { Self.displayName(for: name) }

    /// `displayName` for a shortcut called `name` (also for listed shortcuts that are not tiles, `ShortcutsCatalog`).
    nonisolated static func displayName(for name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty
            ? String(localized: "Untitled shortcut", bundle: .module, comment: "Quick Apps: name of a shortcut whose name is empty")
            : trimmed
    }
}
