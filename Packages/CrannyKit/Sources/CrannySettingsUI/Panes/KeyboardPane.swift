// CrannySettingsUI/Panes/KeyboardPane.swift — Settings ▸ Keyboard (DESIGN.md §11.1, §16): a recorder per global shortcut
// in the design's order (Open Cranny ⌃⌥N on; Open Tray, New note, Start timer, Toggle pin, Pause activities off by
// default; then any other module's), the type-to-capture target, and a read-only reference of the keys inside Cranny
// (the same data as the hold-⌘ overlay).
import AppKit
import CrannyCore
import Foundation
import SwiftUI

struct KeyboardPane: View {
    let registry: ModuleRegistry
    /// The enabled macOS shortcuts: the well-known defaults until the domain is read (off the main actor).
    @State private var system = SystemShortcuts.knownDefaults

    private var settings: SettingsStore { registry.services.settings }

    var body: some View {
        let shortcuts = KeyboardRows.ordered(registry.shortcuts)
        let combos = shortcuts.map { (shortcut: $0, combo: KeyboardRows.effectiveCombo($0, settings: settings)) }
        SettingsForm(.keyboard) {
            Section {
                if shortcuts.isEmpty {
                    Text("No shortcuts are available.", bundle: .module, comment: "Settings ▸ Keyboard: no module registered a shortcut")
                        .foregroundStyle(.secondary)
                }
                ForEach(shortcuts) { shortcut in
                    ShortcutRow(shortcut: shortcut, settings: settings, app: registry.services.app,
                                others: combos.compactMap { entry in
                                    guard entry.shortcut.id != shortcut.id, let combo = entry.combo else { return nil }
                                    return (entry.shortcut.title, combo)
                                },
                                system: system)
                }
            } header: {
                Text("Shortcuts", bundle: .module, comment: "Settings ▸ Keyboard: section header (global shortcuts)")
            } footer: {
                Text("These work in every app and need no special permission.", bundle: .module,
                     comment: "Settings ▸ Keyboard: footer of the shortcuts section")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section {
                CaptureTargetRow(registry: registry)
            }
            KeyboardReference()
        }
        .task {
            // Read when the pane appears and again whenever Cranny becomes active (System Settings may have changed them).
            system = await SystemShortcuts.load()
            for await _ in NotificationCenter.default.notifications(named: NSApplication.didBecomeActiveNotification) {
                system = await SystemShortcuts.load()
            }
        }
    }
}

/// "Type to capture": where the first typed keys go when Cranny was opened from the keyboard (DESIGN.md §7.5).
private struct CaptureTargetRow: View {
    let registry: ModuleRegistry

    private var choices: [Choice<String?>] {
        KeyboardRows.captureTargets(registry).map { Choice(value: $0.id, label: $0.title) }
            + [Choice(value: nil, label: ShortcutRecorder.offTitle)]
    }

    var body: some View {
        ChoiceRow(KeyboardRows.typeToCapture, settings: registry.services.settings, key: CoreSettings.typeToCapture, choices: choices,
                  footnote: String(localized: "When you open Cranny with the keyboard, just start typing to write a note or a to-do.",
                                   bundle: .module, comment: "Settings ▸ Keyboard: footnote of Type to capture"))
    }
}

extension View {
    /// Runs `action` whenever the app becomes active (another app may have changed the system shortcuts).
    func onReceiveAppActivation(_ action: @escaping @MainActor () -> Void) -> some View {
        task {
            for await _ in NotificationCenter.default.notifications(named: NSApplication.didBecomeActiveNotification) { action() }
        }
    }
}

#Preview("Keyboard") {
    let registry = ModuleRegistry(services: .preview())
    registry.add(shortcut: GlobalShortcut(id: .openNook, title: "Open Cranny", defaultCombo: .openNookDefault) {})
    registry.add(shortcut: GlobalShortcut(id: .togglePin, title: "Toggle pin") {})
    return KeyboardPane(registry: registry).frame(width: 650, height: 700)
}
