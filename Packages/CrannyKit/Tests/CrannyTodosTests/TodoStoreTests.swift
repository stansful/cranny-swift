import CrannyCore
import Foundation
import Testing
@testable import CrannyTodos

/// Persistence in temporary directories (ARCHITECTURE.md §10.7 "store tests: persistence, corrupt file").
struct TodoStoreTests {
    /// A fresh `todos.json` location under a throw-away `AppPaths` root (never the user's files).
    private func temporaryStorage() -> TodoStorage { TodoStorage(paths: .temporary()) }

    private func store(_ storage: TodoStorage) async -> TodoStore {
        let store = TodoStore(storage: storage, saveDelay: .seconds(60))     // tests save explicitly
        await store.load()
        return store
    }

    @Test func storageLivesUnderTheModuleDirectory() {
        let paths = AppPaths.temporary()
        #expect(TodoStorage(paths: paths).url == paths.root.appending(path: "todos").appending(path: "todos.json"))
    }

    @Test func missingFileStartsEmptyAndReady() async throws {
        let storage = temporaryStorage()
        #expect(try storage.loadNow() == .missing)
        let store = await store(storage)
        #expect(store.phase == .ready)
        #expect(store.list.isEmpty)
    }

    @Test func savedListLoadsInTheSameOrder() async throws {
        let storage = temporaryStorage()
        let first = await store(storage)
        first.update { list in
            for title in ["one", "two", "three"] { list.insert(Todo(title: title), after: nil) }
            list.setDone(true, for: list.items[1].id, at: Date(timeIntervalSinceReferenceDate: 500))
        }
        await first.save()
        let second = await store(storage)
        #expect(second.list == first.list)
        #expect(second.list.items.map(\.title) == ["one", "two", "three"])
        #expect(second.list.items[1].completed == Date(timeIntervalSinceReferenceDate: 500))
    }

    @Test func blankDraftsAreNeverSaved() async throws {
        let storage = temporaryStorage()
        let first = await store(storage)
        first.update { $0.insert(Todo(title: "keep"), after: nil); $0.insert(Todo(title: "  "), after: nil) }
        await first.save()
        let second = await store(storage)
        #expect(second.list.items.map(\.title) == ["keep"])
    }

    @Test func corruptFileIsMovedAsideAndTheListStartsEmpty() async throws {
        let storage = temporaryStorage()
        try FileManager.default.createDirectory(at: storage.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{ not json".utf8).write(to: storage.url)
        let outcome = try storage.loadNow()
        guard case .corrupt(let aside) = outcome else { Issue.record("expected .corrupt, got \(outcome)"); return }
        #expect(FileManager.default.fileExists(atPath: aside.path))
        #expect(!FileManager.default.fileExists(atPath: storage.url.path))
        #expect(aside.lastPathComponent.hasPrefix("todos.json.corrupt-"))

        // The store recovers: empty, ready, and the next save writes a valid file.
        try Data("[1, 2".utf8).write(to: storage.url)
        let store = await store(storage)
        #expect(store.phase == .ready && store.list.isEmpty)
        store.update { $0.insert(Todo(title: "fresh"), after: nil) }
        await store.save()
        guard case .loaded(let document) = try storage.loadNow() else { Issue.record("not saved"); return }
        #expect(document.items.map(\.title) == ["fresh"])
        #expect(document.version == TodoDocument.currentVersion)
    }

    @Test func corruptFilesInTheSameSecondKeepSeparateCopies() async throws {
        let storage = temporaryStorage()
        let directory = storage.url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var asides: [URL] = []
        for junk in ["{ first", "{ second"] {
            try Data(junk.utf8).write(to: storage.url)
            guard case .corrupt(let aside) = try storage.loadNow() else { Issue.record("expected .corrupt"); return }
            asides.append(aside)
        }
        #expect(asides[0] != asides[1])
        #expect(try asides.map { try String(contentsOf: $0, encoding: .utf8) } == ["{ first", "{ second"])
        let same = TodoStorage.asideURL(for: storage.url, date: Date(timeIntervalSince1970: 7))
        #expect(same != TodoStorage.asideURL(for: storage.url, date: Date(timeIntervalSince1970: 7)))
    }

    @Test func corruptFileThatCannotBeMovedAsideFailsAndIsNeverOverwritten() async throws {
        // A read-only directory: the file can be read but not renamed (and nothing can be written next to it).
        let storage = temporaryStorage()
        let directory = storage.url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("{ not json".utf8).write(to: storage.url)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: directory.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path) }
        #expect(throws: (any Error).self) { try storage.loadNow() }

        let store = await store(storage)
        #expect(store.phase == .failed)
        store.update { $0.insert(Todo(title: "x"), after: nil) }
        await store.save()
        store.flush()
        // Writable again: still nothing may replace the corrupt file until a load has moved it aside.
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path)
        await store.save()
        store.flush()
        #expect(try String(contentsOf: storage.url, encoding: .utf8) == "{ not json")
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["todos.json"])

        // "Try again" (a reload) now succeeds: the file goes aside and the list is usable.
        await store.load()
        #expect(store.phase == .ready)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).contains { $0.hasPrefix("todos.json.corrupt-") })
    }

    @Test func unreadableFileFailsAndIsNeverOverwritten() async throws {
        // A directory where the file should be: reading throws something other than "no such file".
        let storage = temporaryStorage()
        try FileManager.default.createDirectory(at: storage.url, withIntermediateDirectories: true)
        let store = await store(storage)
        #expect(store.phase == .failed)
        store.update { $0.insert(Todo(title: "x"), after: nil) }
        await store.save()
        store.flush()
        var isDirectory: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: storage.url.path, isDirectory: &isDirectory) && isDirectory.boolValue)
        #expect(!store.saveFailed)
    }

    @Test func toDosCreatedBeforeTheFileLoadedAreKept() async throws {
        let storage = temporaryStorage()
        try storage.writeNow(TodoDocument(items: [Todo(title: "saved")]), revision: 1)
        let store = TodoStore(storage: storage, saveDelay: .seconds(60))
        store.update { $0.insert(Todo(title: "typed early"), after: nil) }
        await store.load()
        #expect(store.list.items.map(\.title) == ["saved", "typed early"])
        await store.save()
        guard case .loaded(let document) = try storage.loadNow() else { Issue.record("not saved"); return }
        #expect(document.items.map(\.title) == ["saved", "typed early"])
    }

    @Test func flushWritesSynchronously() async throws {
        let storage = temporaryStorage()
        let store = await store(storage)
        store.update { $0.insert(Todo(title: "at quit"), after: nil) }
        store.flush()
        guard case .loaded(let document) = try storage.loadNow() else { Issue.record("not flushed"); return }
        #expect(document.items.map(\.title) == ["at quit"])
    }

    @Test func anOlderRevisionNeverOverwritesANewerOne() throws {
        let storage = temporaryStorage()
        try storage.writeNow(TodoDocument(items: [Todo(title: "new")]), revision: 5)
        try storage.writeNow(TodoDocument(items: [Todo(title: "old")]), revision: 4)
        guard case .loaded(let document) = try storage.loadNow() else { Issue.record("missing"); return }
        #expect(document.items.map(\.title) == ["new"])
    }

    @Test func debouncedSaveWritesAfterTheLastEdit() async throws {
        let storage = temporaryStorage()
        let store = TodoStore(storage: storage, saveDelay: .milliseconds(20))
        await store.load()
        store.update { $0.insert(Todo(title: "a"), after: nil) }
        store.update { $0.insert(Todo(title: "b"), after: nil) }
        for _ in 0..<100 {
            if case .loaded(let document) = try storage.loadNow(), document.items.count == 2 { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        Issue.record("the debounced save never happened")
    }

    @Test func saveFailureIsReportedAndRetried() async throws {
        let paths = AppPaths.temporary()
        let store = await store(TodoStorage(paths: paths))
        #expect(store.phase == .ready)
        // Now the parent of todos.json becomes a plain file: every write fails.
        try FileManager.default.createDirectory(at: paths.root, withIntermediateDirectories: true)
        try Data().write(to: paths.root.appending(path: "todos"))
        store.update { $0.insert(Todo(title: "x"), after: nil) }
        await store.save()
        #expect(store.saveFailed)
        try FileManager.default.removeItem(at: paths.root.appending(path: "todos"))
        store.retrySave()
        for _ in 0..<100 where store.saveFailed { try await Task.sleep(for: .milliseconds(10)) }
        #expect(!store.saveFailed)
    }

    @Test func documentsDecodeLeniently() throws {
        // Unknown keys (a later version) are ignored.
        let json = #"{"version":1,"future":true,"items":[{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","title":"x","isDone":false,"created":0}]}"#
        let document = try JSONDecoder().decode(TodoDocument.self, from: Data(json.utf8))
        #expect(document.items.map(\.title) == ["x"])
    }
}
