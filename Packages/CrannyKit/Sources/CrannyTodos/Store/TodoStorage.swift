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
        /// The file could not be decoded. It was renamed aside (`movedTo`, nil if even that failed) and the
        /// list starts empty, the same policy as Core's `JSONFileStore`.
        case corrupt(movedTo: URL?)
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

    /// Throws only when the file exists but cannot be read (permissions, I/O); the store then refuses to save,
    /// so an unreadable list is never overwritten by an empty one.
    func loadNow() throws -> LoadOutcome {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return .missing
        }
        do {
            return .loaded(try JSONDecoder().decode(TodoDocument.self, from: data))
        } catch {
            let aside = url.appendingPathExtension("corrupt-\(Int(Date().timeIntervalSince1970))")
            let moved = (try? FileManager.default.moveItem(at: url, to: aside)) != nil
            log.error("corrupt \(self.url.lastPathComponent, privacy: .public), moved aside: \(moved, privacy: .public); \(error.localizedDescription, privacy: .public)")
            return .corrupt(movedTo: moved ? aside : nil)
        }
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
