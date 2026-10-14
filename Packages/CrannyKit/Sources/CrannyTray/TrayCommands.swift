// CrannyTray/TrayCommands.swift — ⌘K commands (DESIGN.md §6.4: "Clear Tray" among the actions) and the Tray's port
// into the shell (`TrayIntake`, ARCHITECTURE.md §3.9): the header badge, the drag catch view and the fallback for
// drops no zone took (§5.6), so a dropped file is never lost.
import CrannyCore
import Foundation
import Observation
import SwiftUI
import UniformTypeIdentifiers

final class TrayCommands: PaletteCommandProvider {
    let store: TrayStore
    init(store: TrayStore) { self.store = store }

    func commands(matching query: String) -> [PaletteCommand] {
        let kind = String(localized: "Tray", bundle: .module, comment: "Tray: module name (page tab, Settings pane, ⌘K result kind)")
        let files = String(localized: "files", bundle: .module, comment: "Settings search and ⌘K keyword: files")
        var list = [
            PaletteCommand(id: "tray.open", title: String(localized: "Open Tray", bundle: .module, comment: "Files widget button, ⌘K command and Settings ▸ Keyboard shortcut: show the Tray page"),
                           kind: kind, symbol: "tray.full.fill", keywords: [files]) { [store] in
                store.notch.open(page: .tray, focus: nil, reason: .keyboard)
            },
        ]
        if !store.items.isEmpty {
            let title = String(localized: "Clear Tray", bundle: .module, comment: "Settings ▸ Tray and command palette: remove every item from the Tray (confirmation button, command)")
            list.append(PaletteCommand(id: "tray.clear", title: title,
                                       kind: kind, symbol: "trash", keywords: [files]) { [store] in store.clear() })
        }
        guard !query.isEmpty else { return list }
        return list.filter { command in
            command.title.localizedCaseInsensitiveContains(query) || command.keywords.contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }
}

/// `services.tray`: what the shell and CrannyNotchUI may ask of the Tray.
@MainActor @Observable final class TrayIntakeService: TrayIntake {
    @ObservationIgnored let store: TrayStore
    init(store: TrayStore) { self.store = store }

    var itemCount: Int { store.items.count }

    func catchView(for types: [UTType]) -> AnyView { AnyView(CatchView(store: store, types: types)) }

    func accept(_ payload: DropPayload) async -> Bool { await store.keep(payload.fileURLs) }
}
