// CrannyTodos/Store/TodoList.swift — the ordered list and every edit to it, as a pure value type
// (unit-tested; no I/O, no UI). The order is the user's: new items go where they are created and
// completed items keep their place, so unchecking one puts it back where it was (DESIGN.md §7.6).
import Foundation

/// Direction of a keyboard reorder (⌘↑ / ⌘↓) or of moving between rows (↑ / ↓).
nonisolated enum TodoMoveDirection: Sendable, Equatable {
    case up, down
}

/// A to-do taken out of the list, with where it was, so Undo can put it back exactly.
nonisolated struct TodoRemoval: Equatable, Sendable {
    let todo: Todo
    let index: Int
}

nonisolated struct TodoList: Equatable, Sendable {
    private(set) var items: [Todo]

    init(_ items: [Todo] = []) { self.items = items }

    // MARK: Queries

    var isEmpty: Bool { items.isEmpty }
    /// Open to-dos ("3 left"); drafts that are still blank do not count.
    var remainingCount: Int { items.lazy.filter { !$0.isDone && !$0.title.isBlank }.count }
    var completedCount: Int { items.lazy.filter(\.isDone).count }

    func index(of id: Todo.ID) -> Int? { items.firstIndex { $0.id == id } }
    func item(_ id: Todo.ID) -> Todo? { items.first { $0.id == id } }

    /// What the widget shows: open to-dos, plus completed ones while "Hide completed" is off or while they
    /// still linger after being checked (struck through for 1.2 s before they collapse).
    func visible(hidesCompleted: Bool, lingering: Set<Todo.ID>) -> [Todo] {
        guard hidesCompleted else { return items }
        return items.filter { !$0.isDone || lingering.contains($0.id) }
    }

    /// The row before or after `id` among `visible` (keyboard navigation), nil at either end.
    static func neighbor(of id: Todo.ID, _ direction: TodoMoveDirection, in visible: [Todo.ID]) -> Todo.ID? {
        guard let i = visible.firstIndex(of: id) else { return nil }
        let j = direction == .up ? i - 1 : i + 1
        return visible.indices.contains(j) ? visible[j] : nil
    }

    // MARK: Edits

    /// Inserts `todo` right after `anchor`, or at the end when `anchor` is nil or gone. Returns its index.
    @discardableResult
    mutating func insert(_ todo: Todo, after anchor: Todo.ID?) -> Int {
        let at = anchor.flatMap { index(of: $0) }.map { $0 + 1 } ?? items.count
        items.insert(todo, at: at)
        return at
    }

    @discardableResult
    mutating func remove(_ id: Todo.ID) -> TodoRemoval? {
        guard let i = index(of: id) else { return nil }
        return TodoRemoval(todo: items.remove(at: i), index: i)
    }

    /// Puts removed to-dos back at their old positions (removals in ascending index order, as returned).
    mutating func restore(_ removals: [TodoRemoval]) {
        for removal in removals.sorted(by: { $0.index < $1.index }) where index(of: removal.todo.id) == nil {
            items.insert(removal.todo, at: min(removal.index, items.count))
        }
    }

    mutating func setTitle(_ title: String, for id: Todo.ID) {
        guard let i = index(of: id) else { return }
        items[i].title = Self.sanitized(title)
    }

    /// Checks or unchecks; stamps `completed`. Returns false if nothing changed.
    @discardableResult
    mutating func setDone(_ done: Bool, for id: Todo.ID, at date: Date) -> Bool {
        guard let i = index(of: id), items[i].isDone != done else { return false }
        items[i].isDone = done
        items[i].completed = done ? date : nil
        return true
    }

    /// ⌘↑ / ⌘↓: swaps `id` with the neighbouring *visible* to-do, so hidden completed items never make a
    /// keypress look like it did nothing. Returns false at either end.
    @discardableResult
    mutating func move(_ id: Todo.ID, _ direction: TodoMoveDirection, visible: Set<Todo.ID>) -> Bool {
        guard let from = index(of: id) else { return false }
        switch direction {
        case .up:
            guard let to = items[..<from].lastIndex(where: { visible.contains($0.id) }) else { return false }
            let todo = items.remove(at: from)
            items.insert(todo, at: to)
        case .down:
            guard let to = items[(from + 1)...].firstIndex(where: { visible.contains($0.id) }) else { return false }
            let todo = items.remove(at: from)
            items.insert(todo, at: to)          // `to` shifted down by one: this lands right after the neighbour
        }
        return true
    }

    /// "Delete completed". Returns what was removed, in ascending index order, for Undo.
    mutating func removeCompleted() -> [TodoRemoval] {
        let removals = items.indices.filter { items[$0].isDone }.map { TodoRemoval(todo: items[$0], index: $0) }
        items.removeAll(where: \.isDone)
        return removals
    }

    /// Drops blank drafts (on load: they are never meant to be saved).
    mutating func removeBlank() { items.removeAll { $0.title.isBlank } }

    // MARK: Text

    /// A title is one line: line breaks and tabs (pasted text) become spaces.
    static func sanitized(_ title: String) -> String {
        guard title.contains(where: { $0.isNewline || $0 == "\t" }) else { return title }
        return String(title.map { $0.isNewline || $0 == "\t" ? " " : $0 })
    }

    /// The title as stored when editing ends.
    static func trimmed(_ title: String) -> String { title.trimmingCharacters(in: .whitespacesAndNewlines) }
}
