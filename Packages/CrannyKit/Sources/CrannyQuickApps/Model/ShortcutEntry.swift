// CrannyQuickApps/Model/ShortcutEntry.swift — a persisted Shortcuts.app shortcut (`QuickAppsSettings.shortcuts`).
import Foundation

/// A Shortcuts.app shortcut on the launcher. It runs by identifier, so renaming it in Shortcuts keeps the tile;
/// the name is refreshed whenever Cranny reads the list. Shortcuts has no API for a shortcut's own glyph or colour
/// (R3 §6), so the user picks them; without a choice the tile shows the first letter on a hue hashed from the name.
public nonisolated struct ShortcutEntry: Codable, Hashable, Sendable, Identifiable {
    /// The Shortcuts.app identifier (an uppercase UUID string, as `shortcuts list --show-identifiers` prints it).
    public var id: String
    /// The last known name.
    public var name: String
    /// An SF Symbol chosen by the user; nil shows the first letter of the name.
    public var symbol: String?
    /// A colour chosen by the user; nil uses a stable hue hashed from the name.
    public var tint: ShortcutTint?

    /// A shortcut tile with the given appearance (nil = automatic).
    public init(id: String, name: String, symbol: String? = nil, tint: ShortcutTint? = nil) {
        self.id = id; self.name = name; self.symbol = symbol; self.tint = tint
    }
}
