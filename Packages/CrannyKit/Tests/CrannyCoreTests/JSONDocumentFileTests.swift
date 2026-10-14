import Foundation
import Testing
@testable import CrannyCore

private struct Note: Codable, Equatable, Sendable {
    var text: String
    var date = Date(timeIntervalSinceReferenceDate: 0)
}

/// A fresh temporary folder per test (removed by the caller).
private func folder() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appending(path: "cranny-docfile-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

@Suite("JSON document file") struct JSONDocumentFileTests {
    @Test func missingLoadedAndCorruptAreTellApart() throws {
        let dir = try folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = JSONDocumentFile<Note>(url: dir.appending(path: "sub/notes.json"))
        #expect(try file.load() == .missing)
        #expect(try file.write(Note(text: "a"), revision: 1))                       // creates the folder
        #expect(try file.load() == .loaded(Note(text: "a")))

        // Two corrupt loads within one second never collide: each copy keeps its own name.
        for _ in 0..<2 {
            try Data("{ not json".utf8).write(to: file.url)
            guard case .corrupt(let aside) = try file.load() else { Issue.record("not corrupt"); return }
            #expect(FileManager.default.fileExists(atPath: aside.path))
            #expect(!FileManager.default.fileExists(atPath: file.url.path))         // never left where a save lands
        }
        let asides = try FileManager.default.contentsOfDirectory(atPath: file.url.deletingLastPathComponent().path)
            .filter { $0.hasPrefix("notes.json.corrupt-") }
        #expect(asides.count == 2)
    }

    @Test func anUnreadableFileIsAnErrorNotAMissingOne() throws {
        let dir = try folder()
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: dir.appending(path: "notes.json").path)
            try? FileManager.default.removeItem(at: dir)
        }
        let url = dir.appending(path: "notes.json")
        let file = JSONDocumentFile<Note>(url: url)
        try file.write(Note(text: "the only copy"), revision: 1)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: url.path)
        #expect(throws: (any Error).self) { try file.load() }                     // not `.missing`: never saved over
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        #expect(try file.load() == .loaded(Note(text: "the only copy")))
    }

    @Test func storeRefusesToSaveOverAnUnreadableFile() async throws {
        let dir = try folder()
        let url = dir.appending(path: "index.json")
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            try? FileManager.default.removeItem(at: dir)
        }
        try JSONDocumentFile<Note>(url: url).write(Note(text: "kept"), revision: 1)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: url.path)
        let store = JSONFileStore(url: url, defaultValue: Note(text: "default"))
        #expect(await store.load() == Note(text: "default"))
        await #expect(throws: JSONFileStoreError.unreadableFile(url)) { try await store.save(Note(text: "new")) }
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        #expect(try JSONDocumentFile<Note>(url: url).load() == .loaded(Note(text: "kept")))
        #expect(await store.load() == Note(text: "kept"))                         // readable again: saves work
        try await store.save(Note(text: "new"))
        #expect(await store.load() == Note(text: "new"))
    }

    @Test func anOlderRevisionNeverReplacesANewerOne() async throws {
        let dir = try folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = JSONDocumentFile<Note>(url: dir.appending(path: "todos.json"))
        #expect(try file.write(Note(text: "flushed at quit"), revision: 2))
        #expect(try !file.write(Note(text: "slow background save"), revision: 1))
        #expect(try !file.write(Note(text: "same revision"), revision: 2))
        #expect(try file.load() == .loaded(Note(text: "flushed at quit")))

        // Many background writes in any order: the newest revision is what stays, and no staged file is left behind.
        try await withThrowingTaskGroup(of: Bool.self) { group in
            for revision in (3...40).shuffled() {
                group.addTask { try await file.writeInBackground(Note(text: "\(revision)"), revision: revision) }
            }
            for try await _ in group {}
        }
        #expect(try await file.loadInBackground() == .loaded(Note(text: "40")))
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path) == ["todos.json"])
    }

    @Test func iso8601DatesWhenAsked() throws {
        let dir = try folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = JSONDocumentFile<Note>(url: dir.appending(path: "index.json"), dateCoding: .iso8601)
        try file.write(Note(text: "x", date: Date(timeIntervalSince1970: 0)), revision: 1)
        let json = try String(contentsOf: file.url, encoding: .utf8)
        #expect(json.contains("1970-01-01T00:00:00Z"))
        #expect(try file.load() == .loaded(Note(text: "x", date: Date(timeIntervalSince1970: 0))))
    }
}
