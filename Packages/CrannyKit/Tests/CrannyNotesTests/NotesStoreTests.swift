// NotesStore on temporary folders (never the user's AppPaths): round trips, crash orders, corrupt index,
// stale writes. "No data loss across kill -9": a new store instance must read back what the last save wrote.
import CrannyCore
import Foundation
import Testing
@testable import CrannyNotes

@Suite("Notes store") final class NotesStoreTests {
    private nonisolated let paths = AppPaths.temporary()

    deinit { try? FileManager.default.removeItem(at: paths.root.deletingLastPathComponent()) }
    private var store: NotesStore { NotesStore(paths: paths) }

    private func note(_ title: String, _ text: String, mode: NoteMode = .plain) -> Note {
        Note(title: title, text: text, mode: mode, createdAt: Date(timeIntervalSince1970: 1_000))
    }

    private func save(_ notes: [Note], revision: Int = 1, store: NotesStore? = nil) throws {
        var change = NotesChangeSet(revision: revision, index: NotesIndex(notes: notes.map(\.entry)))
        for n in notes { change.texts[n.id] = n.text }
        try (store ?? self.store).write(change)
    }

    @Test func emptyFolderLoadsNothing() throws {
        let result = try store.loadNow()
        #expect(result.notes.isEmpty)
        #expect(result.recovered == 0)
        #expect(!result.indexWasCorrupt)
    }

    @Test func roundTripKeepsOrderTextAndMetadata() async throws {
        let a = note("deploy.md", "## Release\nlet build = \"1.4.2\"", mode: .code)
        var b = note("Привет 👋", "Текст\r\nс CRLF\n")
        b.language = .swift
        try save([a, b])
        let result = try await NotesStore(paths: paths).load()                  // a fresh instance = after relaunch
        #expect(result.notes.map(\.id) == [a.id, b.id])
        #expect(result.notes[0] == a)
        #expect(result.notes[1].text == "Текст\r\nс CRLF\n")
        #expect(result.notes[1].language == .swift)
        #expect(result.notes[1].title == "Привет 👋")
    }

    @Test func filesAreWhereTheArchitectureSaysAndReadable() throws {
        let a = note("Plan", "one\ntwo")
        try save([a])
        let dir = paths.root.appending(path: "notes")
        #expect(FileManager.default.fileExists(atPath: dir.appending(path: "index.json").path(percentEncoded: false)))
        let body = try String(contentsOf: dir.appending(path: "\(a.id.uuidString).md"), encoding: .utf8)
        #expect(body == "one\ntwo")
    }

    @Test func crashAfterTextBeforeIndexRecoversTheNote() throws {
        let a = note("Kept", "kept")
        try save([a])
        // A new note's text reached the disk, the index did not (kill -9 between the two writes).
        let orphan = UUID()
        try store.write(NotesChangeSet(revision: 2, texts: [orphan: "# Shopping\nmilk"]))
        let result = try NotesStore(paths: paths).loadNow()
        #expect(result.recovered == 1)
        #expect(result.notes.count == 2)
        #expect(result.notes.first?.id == orphan)                               // recovered notes come first
        #expect(result.notes.first?.title == "")                                // the model titles it
        #expect(result.notes.first?.text == "# Shopping\nmilk")
    }

    @Test func crashDuringDeleteDropsTheNote() throws {
        let a = note("A", "a"), b = note("B", "b")
        try save([a, b])
        // Delete: the text file goes first; a crash before the index update leaves B listed without a file.
        try FileManager.default.removeItem(at: paths.root.appending(path: "notes/\(b.id.uuidString).md"))
        let result = try NotesStore(paths: paths).loadNow()
        #expect(result.notes.map(\.id) == [a.id])
    }

    @Test func corruptIndexIsMovedAsideAndTextsRecovered() throws {
        let a = note("A", "alpha"), b = note("B", "beta")
        try save([a, b])
        let dir = paths.root.appending(path: "notes")
        try Data("{ not json".utf8).write(to: dir.appending(path: "index.json"))
        let result = try NotesStore(paths: paths).loadNow()
        #expect(result.indexWasCorrupt)
        #expect(Set(result.notes.map(\.text)) == ["alpha", "beta"])
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path(percentEncoded: false))
        #expect(names.contains { $0.hasPrefix("index.json.corrupt-") })
    }

    @Test func unknownValuesFromANewerVersionFallBack() throws {
        let id = UUID()
        let dir = try paths.directory(for: .notes)
        let json = """
        {"version": 9, "notes": [{"id": "\(id.uuidString)", "title": "Future", "mode": "hologram",
          "language": "klingon", "createdAt": "2026-01-01T00:00:00Z", "modifiedAt": "2026-01-02T00:00:00Z"}]}
        """
        try Data(json.utf8).write(to: dir.appending(path: "index.json"))
        try Data("text".utf8).write(to: dir.appending(path: "\(id.uuidString).md"))
        let result = try store.loadNow()
        #expect(result.notes.count == 1)
        #expect(result.notes[0].mode == .plain)
        #expect(result.notes[0].language == nil)
        #expect(result.notes[0].title == "Future")
    }

    @Test func anOlderChangeSetNeverOverwritesANewerOne() throws {
        let store = store
        let a = note("A", "new text")
        try save([a], revision: 5, store: store)
        var stale = NotesChangeSet(revision: 4, index: NotesIndex(notes: []))
        stale.texts[a.id] = "old text"
        try store.write(stale)                                                  // a slow save finishing late
        let result = try NotesStore(paths: paths).loadNow()
        #expect(result.notes.map(\.text) == ["new text"])
    }

    @Test func removalDeletesTheTextFile() throws {
        let store = store
        let a = note("A", "a"), b = note("B", "b")
        try save([a, b], store: store)
        try store.write(NotesChangeSet(revision: 2, index: NotesIndex(notes: [a.entry]), removed: [b.id]))
        let result = try NotesStore(paths: paths).loadNow()
        #expect(result.notes.map(\.id) == [a.id])
        #expect(result.recovered == 0)
        #expect(!FileManager.default.fileExists(atPath: paths.root.appending(path: "notes/\(b.id.uuidString).md").path(percentEncoded: false)))
    }

    @Test func duplicateIndexEntriesAreIgnored() throws {
        let a = note("A", "a")
        try save([a])
        try store.write(NotesChangeSet(revision: 2, index: NotesIndex(notes: [a.entry, a.entry])))
        #expect(try NotesStore(paths: paths).loadNow().notes.count == 1)
    }

    @Test func registeringDoesNoIO() {
        _ = NotesStore(paths: paths)
        #expect(!FileManager.default.fileExists(atPath: paths.root.path(percentEncoded: false)))
    }
}
