// CrannyTodos/Model/TodoUndo.swift — Undo and Redo for deletions (one to-do, or "Delete completed"), on the
// panel's or the Settings window's undo manager, so ⌘Z brings a to-do back where it was.
import CrannyCore
import Foundation

enum TodoUndo {
    /// After a deletion: Undo puts `removals` back; Redo deletes them again.
    static func registerRestore(_ removals: [TodoRemoval], model: TodosModel, undoManager: UndoManager?, actionName: String) {
        guard let undoManager, !removals.isEmpty else { return }
        undoManager.registerUndo(withTarget: model) { [weak undoManager] model in
            // Undo and Redo are dispatched by the Edit menu (or ⌘Z) on the main thread.
            MainActor.assumeIsolated {
                model.restore(removals)
                registerDelete(removals, model: model, undoManager: undoManager, actionName: actionName)
            }
        }
        undoManager.setActionName(actionName)
    }

    private static func registerDelete(_ removals: [TodoRemoval], model: TodosModel, undoManager: UndoManager?, actionName: String) {
        guard let undoManager else { return }
        undoManager.registerUndo(withTarget: model) { [weak undoManager] model in
            MainActor.assumeIsolated {
                // Highest index first, so every recorded index is the to-do's position in the full list.
                let again = removals.sorted { $0.index > $1.index }.compactMap { model.delete($0.todo.id) }
                registerRestore(again, model: model, undoManager: undoManager, actionName: actionName)
            }
        }
        undoManager.setActionName(actionName)
    }
}
