// CrannyQuickApps/QuickAppsCommands.swift — ⌘K: open a quick app, run a shortcut (DESIGN.md §6.4).
//
// In-memory only (called on every keystroke): the tiles, plus — once the user types — every shortcut of the last
// Shortcuts list. The list is refreshed when the palette opens (`NotchEvent.paletteOpened`), never here.
// Demo mode hides shortcut names as the tiles do: tile shortcuts read "Run Shortcut" (with their ⌥ key), and the
// rest of Shortcuts.app is not listed.
import CrannyCore
import Foundation

final class QuickAppsCommands: PaletteCommandProvider {
    let model: QuickAppsModel
    init(model: QuickAppsModel) { self.model = model }

    func commands(matching query: String) -> [PaletteCommand] {
        var scored: [(score: Int, rank: Int, command: PaletteCommand)] = []
        let tiles = model.tiles
        for (index, tile) in tiles.enumerated() {
            let command = command(for: tile, index: index)
            if let score = CommandMatcher.score([tile.name] + command.keywords, query: query) {
                scored.append((score, index, command))
            }
        }
        // The rest of Shortcuts.app, only for a typed query (an empty palette lists the tiles), never in Demo mode.
        if !model.environment.isDemoMode, !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let onTiles = Set(model.shortcutEntries.map(\.id))
            for (offset, info) in model.shortcutsCatalog.shortcuts.enumerated() where !onTiles.contains(info.id) {
                let entry = ShortcutEntry(id: info.id, name: info.name)
                guard let score = CommandMatcher.score([entry.displayName], query: query) else { continue }
                scored.append((score, tiles.count + offset, runCommand(entry, shortcut: nil)))
            }
        }
        return scored.sorted { ($0.score, -$0.rank) > ($1.score, -$1.rank) }.map(\.command)
    }

    private func command(for tile: LauncherTile, index: Int) -> PaletteCommand {
        switch tile {
        case .app(let app):
            PaletteCommand(id: CommandID("quickapps.open.\(app.bundleID)"),
                           title: String(localized: "Open \(app.name)", bundle: .module, comment: "Command palette: open a quick app (app name)"),
                           kind: String(localized: "App", bundle: .module, comment: "Quick Apps: an app (⌘K result kind, Settings row subtitle)"),
                           symbol: "app.dashed", keywords: [app.bundleID],
                           shortcut: CommandMatcher.optionDigit(index)) { [model] in model.activate(tile) }
        case .shortcut(let entry):
            runCommand(entry, shortcut: CommandMatcher.optionDigit(index))
        }
    }

    private func runCommand(_ entry: ShortcutEntry, shortcut: KeyCombo?) -> PaletteCommand {
        let redacted = model.environment.isDemoMode
        return PaletteCommand(id: CommandID("quickapps.run.\(entry.id)"),
                       title: String(localized: "Run \(model.publicName(of: entry))", bundle: .module, comment: "Command palette: run a Shortcuts.app shortcut (shortcut name)"),
                       kind: QuickAppsModel.neutralShortcutName,
                       symbol: redacted ? ShortcutAppearance.fallbackSymbol : entry.symbol ?? ShortcutAppearance.fallbackSymbol,
                       shortcut: shortcut) { [model] in model.toggleRun(entry) }
    }
}
