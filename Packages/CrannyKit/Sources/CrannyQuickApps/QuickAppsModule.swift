// CrannyQuickApps/QuickAppsModule.swift — the module's single entry point (ARCHITECTURE.md §3.4, §10.4).
//
// Contributes the launcher widget (`quickapps.launcher`), Settings ▸ Shortcuts and ⌘K commands. `register` only
// builds the model and contributes; app lookups and the running-apps subscription start in `onLaunch`; the
// Shortcuts list is read on demand. No permission is needed (the Shortcuts CLI asks for none, R3 §6).
import CrannyCore
import Foundation
import SwiftUI

/// Quick Apps & Shortcuts: launch apps and run Shortcuts.app shortcuts from the open panel.
public enum QuickAppsModule: FeatureModule {
    /// The module's settings namespace and owner tag (`.quickApps`).
    public static var id: ModuleID { .quickApps }

    /// Registers the widget, the Settings pane and the ⌘K provider; work starts in `registry.onLaunch`.
    public static func register(in registry: ModuleRegistry) {
        let model = QuickAppsModel(services: registry.services)
        registry.add(widget: LauncherWidget(model: model))
        registry.add(settingsPage: SettingsPage(
            id: .shortcuts,
            title: String(localized: "Shortcuts", bundle: .module, comment: "Settings sidebar: Quick Apps & Shortcuts pane name (Apple's Shortcuts app)"),
            symbol: "square.2.layers.3d.fill", tint: .indigo, group: .features, order: 2,
            keywords: searchKeywords, previewState: .open) { AnyView(ShortcutsSettingsPane(model: model)) })
        registry.add(commands: QuickAppsCommands(model: model))
        registry.onLaunch {
            await model.start()
            #if DEBUG
            QuickAppsQA.apply(to: model)
            #endif
        }
        registry.onTerminate { model.stop() }
    }

    /// The pane's row labels and synonyms, for Settings search (DESIGN.md §11.3: "dock" → Quick Apps).
    static var searchKeywords: [String] {
        [
            String(localized: "Quick Apps", bundle: .module, comment: "Quick Apps: widget name (widget library, VoiceOver container)"),
            String(localized: "Apps", bundle: .module, comment: "Settings search: keyword for the Shortcuts pane"),
            String(localized: "Dock", bundle: .module, comment: "Settings search: keyword for the Shortcuts pane"),
            String(localized: "Launcher", bundle: .module, comment: "Settings search: keyword for the Shortcuts pane"),
            String(localized: "Symbol", bundle: .module, comment: "Settings ▸ Shortcuts: symbol (popover section, search keyword)"),
            String(localized: "Color", bundle: .module, comment: "Settings ▸ Shortcuts: colour (popover section, search keyword)"),
            String(localized: "Show names under tiles", bundle: .module, comment: "Quick Apps: option toggle (widget options, Settings ▸ Shortcuts)"),
        ]
    }
}
