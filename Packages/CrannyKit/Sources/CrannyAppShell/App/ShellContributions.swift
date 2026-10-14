// CrannyAppShell/App/ShellContributions.swift — the shell's own contributions (ARCHITECTURE.md §10.0).
// Created by WP0, owned by WP16 afterwards: the shell's GlobalShortcuts (Open Cranny, Toggle pin → overlay;
// Pause → PauseController, WP16) and the shell ⌘K provider (WP16) — and nothing else.
import CrannyCore
import Foundation

@MainActor enum ShellContributions {
    static func register(in registry: ModuleRegistry, overlay: OverlayCoordinator) {
        registry.add(shortcut: GlobalShortcut(
            id: .openNook, title: String(localized: "Open Cranny", bundle: .module, comment: "Menu bar and Settings ▸ Keyboard: item and shortcut that open the panel"),
            defaultCombo: .openNookDefault) { [weak overlay] in overlay?.toggleOpen() })
        registry.add(shortcut: GlobalShortcut(
            id: .togglePin, title: String(localized: "Toggle pin", bundle: .module, comment: "Settings ▸ Keyboard: shortcut name (pins or unpins the open panel)"),
            defaultCombo: nil) { [weak overlay] in overlay?.togglePinned() })
    }
}
