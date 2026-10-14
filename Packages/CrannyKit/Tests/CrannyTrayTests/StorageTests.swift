// TrayStorage on temporary folders: copies, links, temporary sources, deletion of owned copies only, the index.
import CrannyCore
import Foundation
import Testing
import UniformTypeIdentifiers
@testable import CrannyTray

@Suite struct StorageTests {
    let base = Fixtures.folder("storage")
    var storage: TrayStorage {
        TrayStorage(root: base.appending(path: "Tray"), temporaryRoots: [base.appending(path: "Incoming")])
    }

    @Test func copyModeKeepsACopyAndLeavesTheOriginal() async throws {
        let source = Fixtures.folder("user")
        let file = Fixtures.image("hero.png", in: source, width: 64, height: 64)
        let items = await storage.ingest([file], mode: .copy, now: Date())
        let item = try #require(items.first)
        #expect(item.isOwned && item.name == "hero.png")
        #expect(item.typeIdentifier == UTType.png.identifier)
        #expect(item.originalPath == file.standardizedFileURL.path)
        let copy = try #require(storage.ownedURL(item))
        #expect(copy.path.hasPrefix(storage.root.path) && copy.lastPathComponent == "hero.png")
        #expect(try Data(contentsOf: copy) == Data(contentsOf: file))
        #expect(item.size == Fixtures.size(file))
        #expect(FileManager.default.fileExists(atPath: file.path))
    }

    @Test func foldersAreCopiedWithTheirSize() async throws {
        let source = Fixtures.folder("user-folder")
        let folder = source.appending(path: "Assets", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        Fixtures.text("a.txt", in: folder, contents: String(repeating: "a", count: 100))
        Fixtures.text("b.txt", in: folder, contents: String(repeating: "b", count: 50))
        let item = try #require(await storage.ingest([folder], mode: .copy, now: Date()).first)
        #expect(item.size == 150)
        #expect(item.contentType.conforms(to: .folder))
    }

    @Test func linkModeFollowsTheFileWhenItMoves() async throws {
        let source = Fixtures.folder("user-link")
        let file = Fixtures.text("notes.txt", in: source)
        let item = try #require(await storage.ingest([file], mode: .link, now: Date()).first)
        #expect(!item.isOwned)
        let moved = source.appending(path: "renamed.txt")
        try FileManager.default.moveItem(at: file, to: moved)
        let resolved = await storage.resolve([item])
        #expect(resolved.urls[item.id]?.lastPathComponent == "renamed.txt")
        #expect(resolved.refreshed.first?.name == "renamed.txt")
        try FileManager.default.removeItem(at: moved)
        #expect(await storage.resolve([item]).urls[item.id] == nil)          // deleted = missing
    }

    @Test func temporaryFilesAreAlwaysCopied() async throws {
        let incoming = base.appending(path: "Incoming/promise", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: incoming, withIntermediateDirectories: true)
        let file = Fixtures.text("Photo.heic", in: incoming)
        let item = try #require(await storage.ingest([file], mode: .link, now: Date()).first)
        #expect(item.isOwned)
        #expect(item.originalPath == nil)                                  // nothing to dedupe against later
    }

    @Test func onlyOwnedCopiesAreDeleted() async throws {
        let source = Fixtures.folder("user-delete")
        let copied = Fixtures.text("a.txt", in: source)
        let linked = Fixtures.text("b.txt", in: source)
        let owned = try #require(await storage.ingest([copied], mode: .copy, now: Date()).first)
        let link = try #require(await storage.ingest([linked], mode: .link, now: Date()).first)
        let copy = try #require(storage.ownedURL(owned))
        await storage.deleteOwned([owned, link])
        #expect(!FileManager.default.fileExists(atPath: copy.path))
        #expect(FileManager.default.fileExists(atPath: copied.path))
        #expect(FileManager.default.fileExists(atPath: linked.path))
    }

    @Test func orphanedCopiesAreRemoved() async throws {
        let source = Fixtures.folder("user-orphan")
        let kept = try #require(await storage.ingest([Fixtures.text("a.txt", in: source)], mode: .copy, now: Date()).first)
        let orphan = try #require(await storage.ingest([Fixtures.text("b.txt", in: source)], mode: .copy, now: Date()).first)
        await storage.removeOrphans(keeping: [kept])
        #expect(FileManager.default.fileExists(atPath: storage.ownedURL(kept)?.path ?? "-"))
        #expect(!FileManager.default.fileExists(atPath: storage.ownedURL(orphan)?.path ?? "-"))
    }

    @Test func unreadableFilesAreSkipped() async {
        let items = await storage.ingest([URL(filePath: "/nonexistent/\(UUID().uuidString).txt")], mode: .copy, now: Date())
        #expect(items.isEmpty)
    }

    @Test func indexRoundTrips() async throws {
        let source = Fixtures.folder("user-index")
        let items = await storage.ingest([Fixtures.text("a.txt", in: source), Fixtures.text("b.txt", in: source)], mode: .copy, now: Date())
        storage.writeIndexNow(TrayIndex(items: items))
        let loaded = await JSONFileStore(url: storage.indexURL, defaultValue: TrayIndex()).load()
        #expect(loaded.items == items)
        #expect(loaded.version == 1)
    }
}
