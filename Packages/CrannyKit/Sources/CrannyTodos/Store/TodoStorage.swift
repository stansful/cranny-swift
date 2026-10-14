// CrannyTodos/Store/TodoStorage.swift — reads and writes `AppPaths/todos/todos.json`.
//
// Threading: `load()` and `write(_:revision:)` are `@concurrent` (off the main actor, §9.1). The only
// synchronous caller is `TodoStore.flush()` from `applicationWillTerminate`. Writes are serialized by a lock
// and carry the store's revision: a write older than the last one written is skipped, so a slow background
// save can never replace the newer synchronous flush at quit.
import CrannyCore
import Foundation
import os

nonisolated private let log = Log.logger(.todos)

nonisolated final class TodoStorage: Sendable {
    enum LoadOutcome: Equatable, Sendable {
        case loaded(TodoDocument)
        /// First launch: there is no file yet.
        case missing
        /// The file could not be decoded. It was renamed aside to `movedTo` and the list starts empty, the same
        /// policy as Core's `JSONFileStore`. If it cannot be renamed, `load` throws instead: the only copy of the
        /// user's list is never left where the next save would replace it.
        case corrupt(movedTo: URL)
    }

    let url: URL
    private let lastWrittenRevision = OSAllocatedUnfairLock(initialState: Int.min)

    init(url: URL) { self.url = url }

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
    func loadNow() throws -> LoadOutcome {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return .missing
        }
        let decodingError: any Error
        do {
            return .loaded(try JSONDecoder().decode(TodoDocument.self, from: data))
        } catch {
            decodingError = error
        }
        let aside = Self.asideURL(for: url)
        do {
            try FileManager.default.moveItem(at: url, to: aside)
        } catch {
            log.error("corrupt \(self.url.lastPathComponent, privacy: .public) cannot be moved aside, keeping it: \(error.localizedDescription, privacy: .public)")
            throw error
        }
        log.error("corrupt \(self.url.lastPathComponent, privacy: .public), moved aside to \(aside.lastPathComponent, privacy: .public): \(decodingError.localizedDescription, privacy: .public)")
        return .corrupt(movedTo: aside)
    }

    /// `todos.json.corrupt-<seconds>-<8 hex>`: unique, so a second corrupt file in the same second (a retry)
    /// never collides with the first one's copy.
    static func asideURL(for url: URL, date: Date = Date()) -> URL {
        let suffix = UUID().uuidString.prefix(8).lowercased()
        return url.appendingPathExtension("corrupt-\(Int(date.timeIntervalSince1970))-\(suffix)")
    }

    // MARK: Writing

    @concurrent func write(_ document: TodoDocument, revision: Int) async throws {
        try writeNow(document, revision: revision)
    }

    /// Atomic write of `document`, unless a newer revision has already been written.
    func writeNow(_ document: TodoDocument, revision: Int) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(document)
        let url = self.url
        try lastWrittenRevision.withLock { last in
            guard revision > last else { return }
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            last = revision
        }
    }
}
