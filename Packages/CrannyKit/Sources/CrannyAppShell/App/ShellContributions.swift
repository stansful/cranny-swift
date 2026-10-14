// CrannyAppShell/App/ShellContributions.swift — the shell's own contributions (ARCHITECTURE.md §10.0).
// Created by WP0, owned by WP16 afterwards: the shell's GlobalShortcuts (Open Cranny, Toggle pin → overlay;
// Pause → PauseController, WP16) and the shell ⌘K provider (WP16) — and nothing else.
import CrannyCore
import Foundation

@MainActor enum ShellContributions {
    static func register(in registry: ModuleRegistry, overlay: OverlayCoordinator) {
        registry.add(shortcut: GlobalShortcut(
            id: .openNook, title: String(localized: "Open Cranny", bundle: .module, comment: "Menu bar item; global shortcut name (Settings ▸ Keyboard)"),
            defaultCombo: .openNookDefault) { [weak overlay] in overlay?.toggleOpen() })
        registry.add(shortcut: GlobalShortcut(
            id: .togglePin, title: String(localized: "Keep Cranny open", bundle: .module, comment: "Global shortcut name (Settings ▸ Keyboard)"),
            defaultCombo: nil) { [weak overlay] in overlay?.togglePinned() })
    }
}
