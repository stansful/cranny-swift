// CrannyTodos/Store/Todo.swift — one to-do and the file format of `AppPaths/todos/todos.json`
// (ARCHITECTURE.md §10.7). Content, not settings: "Reset All Settings" keeps it (§3.11).
import Foundation

/// One to-do. Persisted: never rename a property (it is a JSON key).
nonisolated struct Todo: Codable, Hashable, Sendable, Identifiable {
    var id: UUID
    /// Single line, sanitized by `TodoList.sanitized(_:)`. Blank only while it is a draft being typed.
    var title: String
    var isDone: Bool
    var created: Date
    /// When it was checked; nil while open.
    var completed: Date?

    init(id: UUID = UUID(), title: String, isDone: Bool = false, created: Date = Date(), completed: Date? = nil) {
        self.id = id
        self.title = title
        self.isDone = isDone
        self.created = created
        self.completed = completed
    }
}

/// `todos.json`. `version` lets a later release migrate the format; unknown keys are ignored when decoding.
nonisolated struct TodoDocument: Codable, Equatable, Sendable {
    static let currentVersion = 1
    var version: Int
    var items: [Todo]

    init(items: [Todo], version: Int = TodoDocument.currentVersion) {
        self.version = version
        self.items = items
    }
}

extension String {
    /// Empty or whitespace only: a draft row that is not a to-do yet (never saved, never counted).
    nonisolated var isBlank: Bool { allSatisfy(\.isWhitespace) }
}
