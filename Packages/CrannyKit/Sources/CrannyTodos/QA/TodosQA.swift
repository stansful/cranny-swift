// CrannyTodos/QA/TodosQA.swift — Debug-only visual QA for the To-dos widget, next to the shell's `--qa-*` hooks
// (docs/CONTRIBUTING.md). Read from the launch arguments' defaults domain, so nothing is persisted:
//
//   -CrannyQATodosFile <path>          use this file instead of AppPaths/todos/todos.json (never the user's list)
//   -CrannyQATodosEditing <n>|new      after loading, edit visible row n (0-based) or a new to-do
//   -CrannyQATodosComplete <n>         check visible row n after -CrannyQATodosCompleteAfter seconds (default 1.5)
//
// Compiled out of Release builds.
import Foundation

#if DEBUG
enum TodosQA {
    private static var defaults: UserDefaults { .standard }

    /// The override of `todos.json`, if any.
    static var storageURL: URL? {
        defaults.string(forKey: "CrannyQATodosFile").map { URL(fileURLWithPath: $0) }
    }

    /// Applies the editing / completion scenario after the list has loaded.
    static func apply(to model: TodosModel) {
        guard storageURL != nil else { return }          // scenarios only ever run on a QA file
        if let editing = defaults.string(forKey: "CrannyQATodosEditing") {
            if editing == "new" {
                model.beginNew(after: nil)
            } else if let index = Int(editing), model.visibleItems.indices.contains(index) {
                model.beginEditing(model.visibleItems[index].id)
            }
        }
        if let complete = defaults.string(forKey: "CrannyQATodosComplete").flatMap(Int.init) {
            let delay = defaults.string(forKey: "CrannyQATodosCompleteAfter").flatMap(Double.init) ?? 1.5
            Task { @MainActor [weak model] in
                try? await Task.sleep(for: .seconds(delay))
                guard let model, model.visibleItems.indices.contains(complete) else { return }
                model.toggle(model.visibleItems[complete].id)
            }
        }
    }
}
#else
enum TodosQA {
    static var storageURL: URL? { nil }
    static func apply(to model: TodosModel) {}
}
#endif
