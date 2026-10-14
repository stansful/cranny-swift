// CrannyTodos/TodosSettings.swift — the module's settings keys (`todos.` namespace, ARCHITECTURE.md §10.7).
// Surfaced in the widget's options (Settings ▸ Layout & Widgets and the card's ⋯ menu), never in a shell pane.
import CrannyCore

/// Settings owned by To-dos. The list itself is content (`todos.json`), not a setting.
public enum TodosSettings {
    /// "Hide completed": a checked to-do is struck through, then collapses after 1.2 s (DESIGN.md §7.6).
    /// Off: checked to-dos stay in place, struck through. Default on.
    public static let hidesCompleted = SettingKey<Bool>(.todos, "hidesCompleted", default: true)
}
