// CrannySettingsUI/Panes/ShellPanes.swift — the panes CrannySettingsUI owns itself (DESIGN.md §11.1):
// General, Appearance, Keyboard, Layout & Widgets, Live Activities, Gestures, Permissions, About.
// Module panes (HUD, Media, Calendar, Shortcuts, Tray) come from `registry.settingsPages`.
// "Reset ‹Pane›…" namespaces follow the rows each pane shows (DESIGN.md §11.1, ARCHITECTURE §10.15): General =
// general, displays (Show on + per-display table) and updates; Appearance = appearance, which includes Notch fit.
import AppKit
import CrannyCore
import Foundation
import SwiftUI

enum ShellPanes {
    @MainActor static func all(registry: ModuleRegistry) -> [SettingsPage] {
        func page(_ id: SettingsPageID, _ title: String, _ symbol: String, _ tint: SettingsIconTint, _ group: SettingsGroup,
                  _ order: Int, namespaces: [ModuleID], preview: PreviewStageState?,
                  view: @escaping @MainActor () -> AnyView) -> SettingsPage {
            SettingsPage(id: id, title: title, symbol: symbol, tint: tint, group: group, order: order,
                         namespaces: namespaces, previewState: preview, makeView: view)
        }
        return [
            page(.general, String(localized: "General", bundle: .module, comment: "Settings sidebar: pane name"), "gearshape.fill", .gray, .top, 0,
                 namespaces: [.general, .displays, .updates], preview: .closed) { AnyView(GeneralPane(registry: registry)) },
            page(.appearance, String(localized: "Appearance", bundle: .module, comment: "Settings sidebar: pane name"), "paintbrush.fill", .purple, .top, 1,
                 namespaces: [.appearance], preview: .open) { AnyView(AppearancePane(registry: registry)) },
            page(.keyboard, String(localized: "Keyboard", bundle: .module, comment: "Settings sidebar: pane name"), "keyboard", .indigo, .top, 2,
                 namespaces: [.keyboard], preview: .open) { AnyView(KeyboardPane(registry: registry)) },
            page(.nookAndWidgets, String(localized: "Layout & Widgets", bundle: .module, comment: "Settings sidebar: pane name (code id `nook`)"),
                 "square.grid.2x2.fill", .blue, .notch, 0, namespaces: [.nook], preview: .open) { AnyView(NookWidgetsPane(registry: registry)) },
            page(.liveActivities, String(localized: "Live Activities", bundle: .module, comment: "Settings sidebar: pane name"),
                 "capsule.tophalf.filled", .pink, .notch, 1, namespaces: [.activities], preview: .activity) { AnyView(LiveActivitiesPane(registry: registry)) },
            page(.gestures, String(localized: "Gestures", bundle: .module, comment: "Settings sidebar: pane name"), "hand.draw.fill", .orange, .notch, 3,
                 namespaces: [.gestures], preview: .closed) { AnyView(GesturesPane(registry: registry)) },
            page(.permissions, String(localized: "Permissions", bundle: .module, comment: "Settings sidebar: pane name"), "hand.raised.fill", .blue, .bottom, 0,
                 namespaces: [], preview: nil) { AnyView(PermissionsPane(registry: registry)) },
            page(.about, String(localized: "About", bundle: .module, comment: "Settings sidebar: pane name"), "info.circle.fill", .gray, .bottom, 1,
                 namespaces: [], preview: nil) { AnyView(AboutPane(registry: registry)) },
        ]
    }

    /// Every searchable row of the shell panes, including the rows the registry contributes (shortcuts, live
    /// activities, widgets), so "new note" finds Keyboard and "timer" finds Live Activities.
    @MainActor static func rows(registry: ModuleRegistry) -> [SettingsRowInfo] {
        GeneralRows.all + AppearanceRows.all + KeyboardRows.all(registry: registry) + LayoutRows.all(registry: registry)
            + ActivitiesRows.all(registry: registry) + GesturesRows.all + PermissionsRows.all(registry: registry) + AboutRows.all
    }
}
