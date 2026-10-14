// CrannyTodos/Model/TodoUndo.swift — Undo and Redo for deletions (one to-do, or "Delete completed"), on the
// panel's or the Settings window's undo manager, so ⌘Z brings a to-do back where it was.
import AppKit
import CrannyCore
import Foundation

enum TodoUndo {
    /// The undo manager of the window the user returns to after acting in `window`. A popover (the card's ⋯
    /// menu, Settings' widget options) or a sheet has an undo manager of its own that goes away when it closes;
    /// its top-level parent's (the panel, the Settings window) is where ⌘Z will be pressed. `fallback` (the
    /// environment's) when the view is not in a window, e.g. options shown as menu items.
    static func undoManager(hostedIn window: NSWindow?, fallback: UndoManager?) -> UndoManager? {
        guard var owner = window else { return fallback }
        while let parent = owner.sheetParent ?? owner.parent { owner = parent }
        return owner.undoManager ?? fallback
    }

    /// "Delete completed" in the widget options (shown in `window`): deletes every checked to-do and registers
    /// Undo / Redo on the undo manager of the window below the options.
    @discardableResult
    static func deleteCompleted(_ model: TodosModel, hostedIn window: NSWindow?, fallback: UndoManager?) -> [TodoRemoval] {
        let removals = model.deleteCompleted()
        registerRestore(removals, model: model, undoManager: undoManager(hostedIn: window, fallback: fallback),
                        actionName: TodosStrings.deleteCompleted)
        return removals
    }

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
