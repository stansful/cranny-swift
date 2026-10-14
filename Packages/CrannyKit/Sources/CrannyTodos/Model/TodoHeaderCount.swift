// CrannyTodos/Model/TodoHeaderCount.swift — what the header's count says (DESIGN.md §7.6 "3 left"). "All done"
// needs something done: an empty list with a blank draft being typed (the first to-do) shows no count at all.
import Foundation

nonisolated enum TodoHeaderCount: Equatable, Sendable {
    /// "3 left": open to-dos with a title.
    case remaining(Int)
    /// "All done": nothing open, and at least one to-do is checked.
    case allDone
    /// No count: nothing to count yet (no to-dos, or only a blank draft).
    case none

    init(remaining: Int, completed: Int) {
        if remaining > 0 {
            self = .remaining(remaining)
        } else if completed > 0 {
            self = .allDone
        } else {
            self = .none
        }
    }

    /// The caption, nil for `.none`.
    var text: String? {
        switch self {
        case .remaining(let count): TodosStrings.remaining(count)
        case .allDone: TodosStrings.allDone
        case .none: nil
        }
    }

    /// The number the caption's numeric transition follows.
    var value: Int {
        if case .remaining(let count) = self { count } else { 0 }
    }
}

extension TodoList {
    var headerCount: TodoHeaderCount { TodoHeaderCount(remaining: remainingCount, completed: completedCount) }
}
