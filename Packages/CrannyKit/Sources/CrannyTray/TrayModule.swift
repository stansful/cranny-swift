// CrannyTray/TrayModule.swift — the module's single entry point (ARCHITECTURE.md §3.4, §10.9): the Tray page, the
// AirDrop and Files widgets, Settings ▸ Tray, ⌘K commands, the Open Tray shortcut and `services.tray` (TrayIntake).
// `register(in:)` stays cheap: models and contributions only; the index is read in `onLaunch`.
import CrannyCore
import Foundation
import SwiftUI

/// Tray: dropped files, AirDrop and pipelines. Registered by the shell's `CompositionRoot`.
public enum TrayModule: FeatureModule {
    /// The module's settings namespace and owner tag (`.tray`).
    public static var id: ModuleID { .tray }

    /// Registers the module's contributions; cheap — the index is read and retention applied in `registry.onLaunch`.
    public static func register(in registry: ModuleRegistry) {
        let services = registry.services
        let directories = TrayQA.directories ?? TrayDirectories.live(paths: services.paths)
        let store = TrayStore(settings: services.settings, notch: services.notch, haptics: services.haptics,
                              system: LiveTraySystem(), directories: directories)
        services.tray = TrayIntakeService(store: store)
        contribute(store, to: registry)
        registry.onLaunch {
            await store.load()
            await TrayQA.seedIfRequested(store)
        }
        registry.onTerminate { store.terminate() }
    }

    /// Everything the Tray adds to the app (split out so tests can register a store on temporary folders).
    @MainActor static func contribute(_ store: TrayStore, to registry: ModuleRegistry) {
        let title = String(localized: "Tray", bundle: .module, comment: "Tray: module name (page tab, Settings pane, ⌘K result kind)")
        registry.add(page: PageDescriptor(id: .tray, title: title, symbol: "tray.full.fill", order: 0,
                                          badge: { store.items.isEmpty ? nil : store.items.count },
                                          makeView: { context in AnyView(TrayPage(store: store, context: context)) }))
        registry.add(widget: AirDropWidget(store: store))
        registry.add(widget: FilesShelfWidget(store: store))
        registry.add(settingsPage: SettingsPage(
            id: .tray, title: title, symbol: "tray.full.fill", tint: .green, group: .features, order: 3,
            keywords: TraySettingsKeywords.all, previewState: .open) { AnyView(TraySettingsPane(store: store)) })
        registry.add(commands: TrayCommands(store: store))
        registry.add(shortcut: GlobalShortcut(
            id: .openTray,
            title: String(localized: "Open Tray", bundle: .module, comment: "Files widget button, ⌘K command and Settings ▸ Keyboard shortcut: show the Tray page"),
            defaultCombo: nil) {
                store.notch.open(page: .tray, focus: nil, reason: .keyboard)
            })
    }
}

/// Settings search terms for the opaque Tray pane: its row labels (ARCHITECTURE.md §3.7).
enum TraySettingsKeywords {
    static var all: [String] {
        [
            String(localized: "Keep dropped files as", bundle: .module, comment: "Settings ▸ Tray: row label"),
            String(localized: "Copies", bundle: .module, comment: "Settings ▸ Tray: keep dropped files as copies (default)"),
            String(localized: "Links to the originals", bundle: .module, comment: "Settings ▸ Tray: keep dropped files as links"),
            String(localized: "Remove items", bundle: .module, comment: "Settings ▸ Tray: row label (retention)"),
            String(localized: "Keep at most", bundle: .module, comment: "Settings ▸ Tray: row label (item cap)"),
            String(localized: "Show the Tray after dropping files", bundle: .module, comment: "Settings ▸ Tray: toggle"),
            String(localized: "AirDrop zone", bundle: .module, comment: "Settings ▸ Tray: toggle"),
            String(localized: "Pinned pipelines", bundle: .module, comment: "Settings ▸ Tray: section header"),
            String(localized: "Your pipelines", bundle: .module, comment: "Settings ▸ Tray: section header"),
            String(localized: "JPEG and HEIC quality", bundle: .module, comment: "Settings ▸ Tray: slider label"),
            String(localized: "Resize to", bundle: .module, comment: "Settings ▸ Tray: row label (maximum dimension)"),
            String(localized: "Save results", bundle: .module, comment: "Settings ▸ Tray: row label (output location)"),
            String(localized: "Name zip archives", bundle: .module, comment: "Settings ▸ Tray: row label (zip naming)"),
            String(localized: "files", bundle: .module, comment: "Settings search and ⌘K keyword: files"),
            "AirDrop", "zip",
        ]
    }
}
