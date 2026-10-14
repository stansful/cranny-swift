// CrannyTodos/Store/TodoStorage.swift — reads and writes `AppPaths/todos/todos.json` through Core's `JSONDocumentFile`.
//
// Threading: `load()` and `write(_:revision:)` are `@concurrent` (off the main actor, §9.1). The only
// synchronous caller is `TodoStore.flush()` from `applicationWillTerminate`. Writes carry the store's revision: a
// write older than the last one written is skipped, so a slow background save can never replace the newer
// synchronous flush at quit.
import CrannyCore
import Foundation

nonisolated final class TodoStorage: Sendable {
    /// `.loaded`, `.missing` (first launch) or `.corrupt(movedTo:)`: the file could not be decoded and was renamed
    /// aside, so the list starts empty. If it cannot be renamed, or the file cannot be read at all, `load` throws
    /// instead: the only copy of the user's list is never left where the next save would replace it.
    typealias LoadOutcome = JSONDocumentFile<TodoDocument>.LoadOutcome

    private let file: JSONDocumentFile<TodoDocument>
    var url: URL { file.url }

    init(url: URL) { file = JSONDocumentFile(url: url) }

    /// `~/Library/Application Support/app.cranny.Cranny/todos/todos.json`. No I/O: the directory is created
    /// by the first write.
    convenience init(paths: AppPaths) {
        self.init(url: paths.root
            .appending(path: ModuleID.todos.rawValue, directoryHint: .isDirectory)
            .appending(path: "todos.json", directoryHint: .notDirectory))
    }

    // MARK: Reading

    @concurrent func load() async throws -> LoadOutcome { try loadNow() }

    /// Throws when the file exists but cannot be read (permissions, I/O), or cannot be decoded *and* cannot be
    /// moved aside. The store then refuses to save, so the user's list is never overwritten by an empty one.
    func loadNow() throws -> LoadOutcome { try file.load() }

    /// `todos.json.corrupt-<seconds>-<8 hex>`: unique, so a second corrupt file in the same second (a retry)
    /// never collides with the first one's copy.
    static func asideURL(for url: URL, date: Date = Date()) -> URL {
        JSONDocumentFile<TodoDocument>.asideURL(for: url, date: date)
    }

    // MARK: Writing

    @concurrent func write(_ document: TodoDocument, revision: Int) async throws {
        try writeNow(document, revision: revision)
    }

    /// Atomic write of `document`, unless a newer revision has already been written.
    func writeNow(_ document: TodoDocument, revision: Int) throws {
        try file.write(document, revision: revision)
    }
}
