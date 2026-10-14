// CrannyTodos/Model/TodoKeyMap.swift — the widget's keyboard map (DESIGN.md §7.6, §16), as pure functions.
//
// Two places take keys:
// • the list, when a row is selected but not being edited (`TodoKeyMap.command(for:…)`):
//     ↑ ↓ select · Space toggle · ↩ edit (on "New to-do": new) · ⌘↑ ⌘↓ reorder · ⌘⌫ delete;
// • the title editor (`TodoEditorCommand`, from the field editor's key bindings):
//     ↩ next row · ⌫ on an empty row deletes it · ↑ ↓ edit the neighbour · ⌘↑ ⌘↓ reorder · Esc stop editing.
// Anything else returns nil and travels on (Tab to the next widget, Esc to close).
import AppKit
import Foundation

/// The keyboard selection inside the list: a to-do, or the trailing "New to-do" row.
nonisolated enum TodoSelection: Hashable, Sendable {
    case item(Todo.ID)
    case newRow
}

/// Keys the list reacts to.
nonisolated enum TodoListKey: Sendable, Equatable {
    case up, down, space, returnKey, deleteBackward
}

/// What a key press asks the list to do.
nonisolated enum TodoListCommand: Equatable, Sendable {
    case select(TodoSelection)
    case toggle(Todo.ID)
    case edit(Todo.ID)
    /// A new to-do at the end, edited at once.
    case newItem
    case move(Todo.ID, TodoMoveDirection)
    case delete(Todo.ID)
}

nonisolated enum TodoKeyMap {
    /// nil = not handled (let it travel). `visible` is the order on screen, without the "New to-do" row.
    static func command(for key: TodoListKey, command: Bool, selection: TodoSelection?,
                        visible: [Todo.ID]) -> TodoListCommand? {
        let rows: [TodoSelection] = visible.map(TodoSelection.item) + [.newRow]
        guard let selection, let index = rows.firstIndex(of: selection) else {
            // Nothing selected yet (focus just arrived): the first arrow selects the first row.
            return key == .up || key == .down ? .select(rows[0]) : nil
        }
        switch (key, selection) {
        case (.up, .item(let id)) where command:
            return visible.first == id ? nil : .move(id, .up)
        case (.down, .item(let id)) where command:
            return visible.last == id ? nil : .move(id, .down)
        case (.up, _) where !command:
            return index > 0 ? .select(rows[index - 1]) : nil
        case (.down, _) where !command:
            return index < rows.count - 1 ? .select(rows[index + 1]) : nil
        case (.space, .item(let id)) where !command:
            return .toggle(id)
        case (.returnKey, .item(let id)) where !command:
            return .edit(id)
        case (.space, .newRow) where !command, (.returnKey, .newRow) where !command:
            return .newItem
        case (.deleteBackward, .item(let id)) where command:
            return .delete(id)
        default:
            return nil
        }
    }

    /// Where the selection goes when its row disappears (deleted, collapsed): the next row, else the previous,
    /// else "New to-do". `oldVisible` is the order before the change.
    static func selection(replacing removed: Todo.ID, oldVisible: [Todo.ID], newVisible: [Todo.ID]) -> TodoSelection {
        guard let i = oldVisible.firstIndex(of: removed) else { return newVisible.first.map(TodoSelection.item) ?? .newRow }
        let survivors = Set(newVisible)
        if let next = oldVisible[(i + 1)...].first(where: survivors.contains) { return .item(next) }
        if let previous = oldVisible[..<i].last(where: survivors.contains) { return .item(previous) }
        return .newRow
    }
}

/// Keys the title editor reacts to, decoded from the field editor's key-binding selectors
/// (`NSTextFieldDelegate.control(_:textView:doCommandBy:)`), so they follow the user's key bindings.
nonisolated enum TodoEditorCommand: Equatable, Sendable {
    /// ↩: keep this title and start the next to-do below it.
    case commit
    /// Esc: stop editing (the row stays selected).
    case cancel
    /// ⌫: deletes the row when its title is empty, else ordinary text editing.
    case deleteBackward
    /// ↑ / ↓: edit the previous / next row.
    case previous, next
    /// ⌘↑ / ⌘↓: move this to-do.
    case moveUp, moveDown

    init?(selector: Selector) {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)): self = .commit
        case #selector(NSResponder.cancelOperation(_:)): self = .cancel
        case #selector(NSResponder.deleteBackward(_:)): self = .deleteBackward
        case #selector(NSResponder.moveUp(_:)): self = .previous
        case #selector(NSResponder.moveDown(_:)): self = .next
        case #selector(NSResponder.moveToBeginningOfDocument(_:)): self = .moveUp
        case #selector(NSResponder.moveToEndOfDocument(_:)): self = .moveDown
        default: return nil
        }
    }
}
