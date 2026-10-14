// CrannyNotes/Store/NotesStore.swift — the files behind the Notes widget: `<dir>/index.json` + `<uuid>.md`
// (ARCHITECTURE.md §10.6). Every write is atomic. Crash safety (`kill -9` at any instant):
//   • create/edit: the text file is written before the index, so a crash leaves at worst an unlisted `.md`,
//     which `load()` recovers ("orphan");
//   • delete: the text file is removed before the index, so a crash leaves a listed note without a file,
//     which `load()` drops (it was being deleted).
// Saves run off the main actor (`@concurrent`); the terminate hook needs a synchronous flush, so both paths
// go through `write(_:)`, serialized by a lock that also drops a change set older than what is on disk.
// Loading fails (the widget shows its error state and "Try again") on any read error other than a missing
// `index.json`: an unreadable index, folder listing or note is never mistaken for "absent", which would make
// the next save overwrite titles, drop notes or replace a text with "".
import CrannyCore
import Foundation
import os

nonisolated private let log = Log.logger(.notes)

/// What a save writes. `revision` grows with every change set the model makes.
nonisolated struct NotesChangeSet: Sendable, Equatable {
    var revision: Int
    /// nil = leave `index.json` alone (the index is never written before the notes were loaded).
    var index: NotesIndex?
    var texts: [UUID: String] = [:]
    var removed: Set<UUID> = []

    var isEmpty: Bool { index == nil && texts.isEmpty && removed.isEmpty }
}

/// The result of reading the folder.
nonisolated struct NotesLoadResult: Sendable, Equatable {
    var notes: [Note]
    /// `.md` files that `index.json` did not list (a crash between the two writes, or a corrupt index).
    var recovered: Int
    /// `index.json` could not be decoded and was moved aside.
    var indexWasCorrupt: Bool
}

nonisolated final class NotesStore: Sendable {
    static let indexName = "index.json"
    static let textExtension = "md"

    private let paths: AppPaths
    /// File name → revision of the change set that last wrote (or removed) it.
    private let written = OSAllocatedUnfairLock(initialState: [String: Int]())

    /// No I/O here (`register(in:)` creates the store): the folder is created by the first load or save.
    init(paths: AppPaths) { self.paths = paths }

    var directory: URL { paths.root.appending(path: ModuleID.notes.rawValue, directoryHint: .isDirectory) }

    // MARK: Loading

    @concurrent func load() async throws -> NotesLoadResult { try loadNow() }

    func loadNow() throws -> NotesLoadResult {
        let fm = FileManager.default
        let dir = try paths.directory(for: .notes)
        let indexURL = dir.appending(path: Self.indexName)
        var corrupt = false
        var index = NotesIndex(notes: [])
        if let data = try Self.contentsIfPresent(indexURL) {
            do {
                index = try Self.decoder.decode(NotesIndex.self, from: data)
            } catch {
                corrupt = true
                let aside = indexURL.appendingPathExtension("corrupt-\(Int(Date().timeIntervalSince1970))")
                try? fm.moveItem(at: indexURL, to: aside)
                log.error("index.json is corrupt, moved aside: \(error.localizedDescription, privacy: .public)")
            }
        }
        let files = try fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey, .creationDateKey])
        var bodies: [UUID: URL] = [:]
        for url in files where url.pathExtension == Self.textExtension {
            if let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent) { bodies[id] = url }
        }
        var notes: [Note] = []
        var seen = Set<UUID>()
        for entry in index.notes where seen.insert(entry.id).inserted {
            guard let url = bodies[entry.id] else {
                log.info("dropping a listed note without a text file (deleted before a crash)")
                continue
            }
            notes.append(Note(id: entry.id, title: entry.title, text: try Self.readText(url), mode: entry.mode,
                              language: entry.language, createdAt: entry.createdAt, modifiedAt: entry.modifiedAt))
        }
        let orphans = try bodies.filter { !seen.contains($0.key) }.map { id, url -> Note in
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .creationDateKey])
            let modified = values?.contentModificationDate ?? Date()
            return Note(id: id, title: "", text: try Self.readText(url), mode: .plain,
                        createdAt: values?.creationDate ?? modified, modifiedAt: modified)
        }.sorted { $0.modifiedAt > $1.modifiedAt }
        if !orphans.isEmpty { log.info("recovered \(orphans.count, privacy: .public) unlisted notes") }
        return NotesLoadResult(notes: orphans + notes, recovered: orphans.count, indexWasCorrupt: corrupt)
    }

    private static func readText(_ url: URL) throws -> String {
        String(decoding: try Data(contentsOf: url), as: UTF8.self)
    }

    /// The file's contents, or nil when it does not exist; every other read error is thrown.
    static func contentsIfPresent(_ url: URL) throws -> Data? {
        do {
            return try Data(contentsOf: url)
        } catch let error where isMissingFile(error) {
            return nil
        }
    }

    /// "No such file" in either of the forms Foundation reports it.
    static func isMissingFile(_ error: any Error) -> Bool {
        let error = error as NSError
        switch error.domain {
        case NSCocoaErrorDomain: return error.code == NSFileReadNoSuchFileError || error.code == NSFileNoSuchFileError
        case NSPOSIXErrorDomain: return error.code == Int(ENOENT)
        default: return false
        }
    }

    // MARK: Saving

    @concurrent func save(_ change: NotesChangeSet) async throws { try write(change) }

    /// Synchronous write for the terminate hook (and the async path above). Serialized; a file is skipped
    /// when a newer change set already wrote it, so a slow older save can never overwrite newer text.
    func write(_ change: NotesChangeSet) throws {
        guard !change.isEmpty else { return }
        try written.withLock { ledger in
            let dir = try paths.directory(for: .notes)
            for (id, text) in change.texts where !change.removed.contains(id) {
                let name = Self.textName(id)
                guard (ledger[name] ?? -1) < change.revision else { continue }
                try Data(text.utf8).write(to: dir.appending(path: name), options: .atomic)
                ledger[name] = change.revision
            }
            for id in change.removed {
                let name = Self.textName(id)
                guard (ledger[name] ?? -1) < change.revision else { continue }
                let url = dir.appending(path: name)
                if FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
                    try FileManager.default.removeItem(at: url)
                }
                ledger[name] = change.revision
            }
            if let index = change.index, (ledger[Self.indexName] ?? -1) < change.revision {
                try Self.encoder.encode(index).write(to: dir.appending(path: Self.indexName), options: .atomic)
                ledger[Self.indexName] = change.revision
            }
        }
    }

    static func textName(_ id: UUID) -> String { "\(id.uuidString).\(textExtension)" }

    // MARK: Coding

    private static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }
    private static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
