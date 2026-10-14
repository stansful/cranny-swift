// CrannySettingsUI/Panes/KeyboardPane.swift — Settings ▸ Keyboard (DESIGN.md §11.1, §16): a recorder per global shortcut
// in the design's order (Open Cranny ⌃⌥N on; Open Tray, New note, Start timer, Toggle pin, Pause activities off by
// default; then any other module's), the type-to-capture target (with a warning and a way to Layout & Widgets while
// its widget is on no page, so typing would do nothing), and a read-only reference of the keys inside Cranny (the same
// data as the hold-⌘ overlay).
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
                if let gap = KeyboardRows.captureGap(registry) {
                    CaptureGapRow(gap: gap, app: registry.services.app)
                }
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

/// The type-to-capture widget is on no page, so typing does nothing (`KeyboardRows.captureGap`): an inline warning
/// under the picker whose button opens Layout & Widgets at that widget's library entry, where Add puts it on a page.
/// The row goes away as soon as the widget is on a page or capture is turned off.
private struct CaptureGapRow: View {
    let gap: KeyboardRows.CaptureGap
    let app: any AppControl
    @Environment(SettingsNavigator.self) private var navigator: SettingsNavigator?

    var body: some View {
        LabeledContent {
            Button {
                show()
            } label: {
                Text("Show in Layout & Widgets", bundle: .module,
                     comment: "Settings ▸ Keyboard: button under the type-to-capture warning; opens Settings ▸ Layout & Widgets at that widget")
            }
        } label: {
            Label {
                Text("The \(gap.title) widget isn’t on any page, so typing does nothing.", bundle: .module,
                     comment: "Settings ▸ Keyboard: warning under Type to capture when its widget is on no page; the argument is the widget's name (Notes, To-dos)")
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                // The system's warning sign in its multicolour rendering, as the other Settings warnings: it follows
                // Light/Dark and Increase Contrast with no literal colour.
                Image(systemName: "exclamationmark.triangle.fill")
                    .symbolRenderingMode(.multicolor)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .contain)
    }

    /// Opens Layout & Widgets, scrolls to the widget's library entry and highlights it (a deep link from previews).
    private func show() {
        let row = LayoutRows.widget(gap.widget, title: gap.title)
        if let navigator {
            navigator.open(row: row)
        } else {
            app.openSettings(SettingsPageID("\(SettingsPageID.nookAndWidgets.rawValue)#widget.\(gap.widget.rawValue)"))
        }
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
