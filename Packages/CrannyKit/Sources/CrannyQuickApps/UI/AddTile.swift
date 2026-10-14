// CrannyQuickApps/UI/AddTile.swift — the trailing "+" tile in edit mode (and the only tile of an empty one-column
// launcher): a dashed squircle that pops up "Add App…" and the user's Shortcuts.app shortcuts (DESIGN.md §7.3).
import AppKit
import CrannyCore
import SwiftUI

struct AddTile: View {
    @Environment(\.cranny) private var theme
    let model: QuickAppsModel
    let metrics: TileMetrics

    var body: some View {
        let p = theme.palette
        let title = String(localized: "Add to Quick Apps", bundle: .module, comment: "Quick Apps: the + tile (tooltip, VoiceOver)")
        Button { PopUpMenu.show(AddMenu.entries(model: model)) } label: {
            TileContent(metrics: metrics, label: model.showsLabels ? String(localized: "Add", bundle: .module, comment: "Quick Apps: add (open panel confirm button, name under the + tile)") : nil,
                        isRunning: false) {
                RoundedRectangle(cornerRadius: metrics.squircleRadius, style: .continuous)
                    .strokeBorder(p.stroke, style: StrokeStyle(lineWidth: StrokeWidth.emphasis, dash: StrokeWidth.dash))
                    .frame(width: metrics.body, height: metrics.body)
                    .overlay {
                        Image(systemName: "plus")
                            .font(.system(size: metrics.glyph, weight: .medium))
                            .foregroundStyle(p.secondaryLabel)
                    }
            }
        }
        .buttonStyle(TileButtonStyle(metrics: metrics))
        .focusable(false)
        .help(title)
        .accessibilityLabel(Text(verbatim: title))
        // Read the Shortcuts list before the menu can open (≈ 20 ms; skipped if read within the last minute).
        .task { await model.shortcutsCatalog.refresh(maximumAge: 60) }
    }
}

/// The add menu: "Add App…", a submenu of shortcuts not on the launcher yet, then edit and Settings items.
@MainActor enum AddMenu {
    static func entries(model: QuickAppsModel) -> [MenuEntry] {
        var entries = [
            MenuEntry(String(localized: "Add App…", bundle: .module, comment: "Quick Apps: add an app with the open panel")) { model.chooseApps() },
            MenuEntry(String(localized: "Add Shortcut", bundle: .module, comment: "Quick Apps: submenu listing Shortcuts.app shortcuts"),
                      submenu: shortcutEntries(model: model)),
            .separator,
        ]
        if model.isEditing {
            entries.append(MenuEntry(String(localized: "Done Editing", bundle: .module, comment: "Quick Apps: menu item, leave edit mode")) {
                model.isEditing = false
            })
        }
        entries.append(MenuEntry(String(localized: "Quick Apps Settings…", bundle: .module, comment: "Quick Apps: opens Settings ▸ Shortcuts")) {
            model.openSettings()
        })
        return entries
    }

    private static func shortcutEntries(model: QuickAppsModel) -> [MenuEntry] {
        let catalog = model.shortcutsCatalog
        let available = catalog.shortcuts.filter { !model.isAdded(shortcut: $0.id) }
        if !available.isEmpty {
            return available.map { info in
                let entry = ShortcutEntry(id: info.id, name: info.name)
                return MenuEntry(entry.displayName, image: ShortcutGlyph.menuImage(for: entry)) { model.add(shortcut: info) }
            }
        }
        switch catalog.state {
        case .idle, .loading:
            return [MenuEntry(disabled: String(localized: "Loading…", bundle: .module, comment: "Quick Apps: shortcut submenu while the list is read"))]
        case .failed(let error):
            return [MenuEntry(disabled: error.localizedDescription)]
        case .loaded:
            return catalog.shortcuts.isEmpty
                ? [MenuEntry(disabled: String(localized: "No shortcuts in Shortcuts yet", bundle: .module, comment: "Quick Apps: shortcut submenu when Shortcuts.app has none")),
                   MenuEntry(String(localized: "Open Shortcuts", bundle: .module, comment: "Quick Apps: opens Shortcuts.app")) { model.launcher.openShortcutsApp() }]
                : [MenuEntry(disabled: String(localized: "All shortcuts are added", bundle: .module, comment: "Quick Apps: shortcut submenu when every shortcut is on the launcher"))]
        }
    }
}

#Preview("Add tile") {
    let model = QuickAppsPreview.model()
    AddTile(model: model, metrics: TileMetrics(tile: 56, showsLabels: false))
        .padding(Space.l)
        .background(.black)
        .crannyThemeRoot(CrannyTheme())
}
