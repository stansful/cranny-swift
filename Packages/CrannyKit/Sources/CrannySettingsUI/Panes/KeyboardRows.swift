// CrannySettingsUI/Panes/KeyboardRows.swift — the rows of Settings ▸ Keyboard and the pure helpers behind them:
// the design's shortcut order, the effective binding of a shortcut and the type-to-capture targets.
import CrannyCore
import Foundation

enum KeyboardRows {
    static var typeToCapture: SettingsRowInfo {
        SettingsRowInfo(.keyboard, "typeToCapture",
                        title: String(localized: "Type to capture", bundle: .module, comment: "Settings ▸ Keyboard: picker Notes / To-dos / Off"))
    }

    /// One row per registered shortcut, searchable by its name ("new note" finds Keyboard).
    static func row(for shortcut: GlobalShortcut) -> SettingsRowInfo {
        SettingsRowInfo(.keyboard, "shortcut.\(shortcut.id.rawValue)", title: shortcut.title,
                        keywords: [String(localized: "hot key", bundle: .module, comment: "Settings search: keyword for global shortcuts")])
    }

    static func all(registry: ModuleRegistry) -> [SettingsRowInfo] {
        ordered(registry.shortcuts).map(row(for:)) + [typeToCapture] + KeyboardReference.rows
    }

    /// DESIGN.md §11.1 order: Open Cranny, Open Tray, New note, Start timer, Toggle pin, Pause activities, then the rest
    /// in registration order.
    static func ordered(_ shortcuts: [GlobalShortcut]) -> [GlobalShortcut] {
        let order: [ShortcutID] = [.openNook, .openTray, .newNote, .startTimer, .togglePin, .pauseActivities]
        return shortcuts.enumerated()
            .sorted { (order.firstIndex(of: $0.element.id) ?? order.count, $0.offset) < (order.firstIndex(of: $1.element.id) ?? order.count, $1.offset) }
            .map(\.element)
    }

    /// The user's binding wins; an explicit nil means off; no entry means the shortcut's default.
    static func effectiveCombo(_ shortcut: GlobalShortcut, settings: SettingsStore) -> KeyCombo? {
        if let binding = settings[CoreSettings.shortcuts][shortcut.id] { return binding }
        return shortcut.defaultCombo
    }

    /// Notes and To-dos (registered titles win), plus any other registered target.
    static func captureTargets(_ registry: ModuleRegistry) -> [(id: String, title: String)] {
        var targets: [(id: String, title: String)] = [
            ("notes", String(localized: "Notes", bundle: .module, comment: "Settings: the Notes feature (glossary: Заметки)")),
            ("todos", String(localized: "To-dos", bundle: .module, comment: "Settings: the To-dos feature (glossary: Задачи)")),
        ]
        for target in registry.captureTargets {
            if let index = targets.firstIndex(where: { $0.id == target.id }) {
                targets[index].title = target.title
            } else {
                targets.append((target.id, target.title))
            }
        }
        return targets
    }
}
