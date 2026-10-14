// CrannyQuickApps/UI/AddTile.swift — the trailing "+" tile in edit mode (and the only tile of an empty one-column
// launcher): a dashed squircle that drops down "Add app…" and the user's Shortcuts.app shortcuts (DESIGN.md §7.3).
//
// Energy: the Shortcuts list is read only when the menu is about to be used — the pointer over "+", keyboard focus
// on it, or the menu opening (`QuickAppsModel.prepareShortcutList`, at most once a minute) — never because the
// tile is on screen. The shortcut submenu follows the list live, so a menu opened mid-read fills in.
import AppKit
import CrannyCore
import SwiftUI

struct AddTile: View {
    @Environment(\.cranny) private var theme
    let model: QuickAppsModel
    let metrics: TileMetrics
    /// Where the menu drops down (the grid also opens it from the keyboard).
    let anchor: MenuAnchor

    var body: some View {
        let p = theme.palette
        let title = String(localized: "Add to Quick Apps", bundle: .module, comment: "Quick Apps: the + tile (tooltip, VoiceOver)")
        Button { Self.showMenu(model: model, anchor: anchor) } label: {
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
        .focusable(false)                       // the grid makes the tile itself focusable (arrows)
        .menuAnchor(anchor)
        .help(title)
        .accessibilityLabel(Text(verbatim: title))
        .onHover { inside in if inside { model.prepareShortcutList() } }
    }

    /// Drops the add menu down under the tile (click, ↩ / Space on the focused tile, VoiceOver).
    static func showMenu(model: QuickAppsModel, anchor: MenuAnchor?) {
        model.prepareShortcutList()
        PopUpMenu.show(AddMenu.entries(model: model), anchor: anchor)
    }
}

/// The add menu: "Add app…", a submenu of shortcuts not on the launcher yet, then edit and Settings items.
@MainActor enum AddMenu {
    static func entries(model: QuickAppsModel) -> [MenuEntry] {
        var entries = [
            MenuEntry(String(localized: "Add app…", bundle: .module, comment: "Quick Apps: add an app with the open panel")) { model.chooseApps() },
            MenuEntry(String(localized: "Add shortcut", bundle: .module, comment: "Quick Apps: submenu listing Shortcuts.app shortcuts"),
                      liveSubmenu: { shortcutEntries(model: model) }),
            .separator,
        ]
        if model.isEditing {
            entries.append(MenuEntry(String(localized: "Done editing", bundle: .module, comment: "Quick Apps: menu item, leave edit mode")) {
                model.isEditing = false
            })
        }
        entries.append(MenuEntry(String(localized: "Quick Apps Settings…", bundle: .module, comment: "Quick Apps: opens Settings ▸ Shortcuts")) {
            model.openSettings()
        })
        return entries
    }

    /// The shortcut submenu for the catalog as it is now (it reads observable state: the menu rebuilds on change).
    static func shortcutEntries(model: QuickAppsModel) -> [MenuEntry] {
        let catalog = model.shortcutsCatalog
        let available = catalog.shortcuts.filter { !model.isAdded(shortcut: $0.id) }
        let redacted = model.environment.isDemoMode
        if !available.isEmpty {
            return available.map { info in
                let entry = ShortcutEntry(id: info.id, name: info.name)
                return MenuEntry(redacted ? QuickAppsModel.neutralShortcutName : entry.displayName,
                                 image: ShortcutMenuImage.image(for: entry, redacted: redacted)) { model.add(shortcut: info) }
            }
        }
        switch catalog.state {
        case .idle, .loading:
            return [MenuEntry(disabled: String(localized: "Loading…", bundle: .module, comment: "Quick Apps: loading (widget while apps are looked up, shortcut submenu while the list is read)"))]
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
    AddTile(model: model, metrics: TileMetrics(tile: 56, showsLabels: false), anchor: MenuAnchor())
        .padding(Space.l)
        .background(.black)
        .crannyThemeRoot(CrannyTheme())
}
