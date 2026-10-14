// CrannyTray/Store/TrayStorage.swift — the Tray's files on disk (ARCHITECTURE.md §7.8): copies under
// `AppPaths.directory(for: .tray)/<uuid>/<name>`, plain (non-sandboxed) bookmarks for links, the JSON index.
// All file work is `@concurrent` (never on the main actor, §9.2). Only items the Tray OWNS are ever deleted, and a
// missing or damaged index never costs a kept copy: the copies are found again from their folders.
import CrannyCore
import Foundation
import os
import UniformTypeIdentifiers

private nonisolated let log = Log.logger(.tray)

/// What reading `index.json` found.
nonisolated enum TrayIndexRead: Sendable, Equatable {
    /// No index yet (first launch, or it was deleted).
    case missing
    case loaded(TrayIndex)
    /// The file exists but cannot be read or decoded (truncated write, a newer format). It was moved aside.
    case unreadable
}

nonisolated struct TrayStorage: Sendable {
    /// The Tray folder: `<uuid>/<name>` copies and `index.json`.
    let root: URL
    /// Files under these folders are temporary (resolved file promises, `NSTemporaryDirectory`): always copied, and
    /// results are never written next to them.
    let temporaryRoots: [URL]

    var indexURL: URL { root.appending(path: "index.json", directoryHint: .notDirectory) }

    /// The URL of an owned copy (no I/O). Linked items resolve through `resolve(_:)`.
    func ownedURL(_ item: TrayItem) -> URL? {
        guard case .owned(let path) = item.location else { return nil }
        return root.appending(path: path, directoryHint: .inferFromPath)
    }

    func isTemporary(_ url: URL) -> Bool { temporaryRoots.contains { OutputPlacement.isInside(url, $0) } }

    // MARK: Adding

    /// Keeps each of `urls` (copy, or link in `.link` mode unless temporary). One result per input, in input order:
    /// files that cannot be kept say why (the store shows an error tile for them).
    @concurrent
    func ingestEach(_ urls: [URL], mode: TrayStorageMode, now: Date) async -> [Result<TrayItem, TrayError>] {
        var results: [Result<TrayItem, TrayError>] = []
        for url in urls {
            if Task.isCancelled { break }
            do {
                let copies = mode == .copy || isTemporary(url)
                results.append(.success(try copies ? copy(url, now: now) : link(url, now: now)))
            } catch {
                log.error("could not keep a file: \(TrayLogCode.of(error), privacy: .public) \(error.localizedDescription, privacy: .private)")
                results.append(.failure(TrayError.keeping(url.lastPathComponent, failedWith: error)))
            }
        }
        return results
    }

    /// The items that could be kept (tests and callers that do not report failures).
    func ingest(_ urls: [URL], mode: TrayStorageMode, now: Date) async -> [TrayItem] {
        await ingestEach(urls, mode: mode, now: now).compactMap { try? $0.get() }
    }

    /// Items that point at files Cranny wrote elsewhere (pipeline results), each with the file it points at. A file
    /// whose bookmark cannot be made is left out together with its URL, so items and URLs never shift.
    @concurrent
    func linkResults(_ urls: [URL], now: Date) async -> [(item: TrayItem, url: URL)] {
        urls.compactMap { url in
            do { return (try link(url, now: now), url) } catch {
                log.error("could not link a result: \(TrayLogCode.of(error), privacy: .public) \(error.localizedDescription, privacy: .private)")
                return nil
            }
        }
    }

    /// Owned items whose original (at `url`) changed since it was copied: a repeat drop copies those again.
    @concurrent
    func changedOriginals(_ candidates: [(url: URL, item: TrayItem)]) async -> Set<UUID> {
        Set(candidates.filter { !FileFingerprint.of($0.url).matches($0.item) }.map(\.item.id))
    }

    /// Copies into `<uuid>/<name>`. The copy is written under a hidden staging name and renamed when complete, so a
    /// crash mid-copy never leaves a half file that looks kept.
    private func copy(_ source: URL, now: Date) throws -> TrayItem {
        let id = UUID()
        let name = source.lastPathComponent
        let folder = root.appending(path: id.uuidString, directoryHint: .isDirectory)
        let fingerprint = FileFingerprint.of(source)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let staging = folder.appending(path: Self.stagingPrefix + name, directoryHint: .inferFromPath)
        let destination = folder.appending(path: name, directoryHint: .inferFromPath)
        do {
            try FileManager.default.copyItem(at: source, to: staging)        // APFS clone when possible
            try FileManager.default.moveItem(at: staging, to: destination)
        } catch {
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
        let temporary = isTemporary(source)
        return TrayItem(id: id, name: name, location: .owned(path: "\(id.uuidString)/\(name)"),
                        size: fingerprint.size, addedAt: now,
                        typeIdentifier: TrayItem.contentType(of: destination).identifier,
                        originalPath: temporary ? nil : source.standardizedFileURL.path,
                        originalModified: temporary ? nil : fingerprint.modified)
    }

    private func link(_ url: URL, now: Date) throws -> TrayItem {
        let bookmark = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        let path = url.standardizedFileURL.path
        return TrayItem(id: UUID(), name: url.lastPathComponent, location: .linked(bookmark: bookmark, path: path),
                        size: Self.size(of: url), addedAt: now, typeIdentifier: TrayItem.contentType(of: url).identifier,
                        originalPath: path)
    }

    /// Hidden name of a copy in progress.
    static let stagingPrefix = ".cranny-partial-"

    // MARK: Resolving

    /// Where each item's file is now (nil = missing), plus items whose bookmark was stale and was refreshed.
    @concurrent
    func resolve(_ items: [TrayItem]) async -> (urls: [UUID: URL], refreshed: [TrayItem]) {
        var urls: [UUID: URL] = [:]
        var refreshed: [TrayItem] = []
        for item in items {
            switch item.location {
            case .owned:
                if let url = ownedURL(item), FileManager.default.fileExists(atPath: url.path) { urls[item.id] = url }
            case .linked(let bookmark, let path):
                var stale = false
                if let url = try? URL(resolvingBookmarkData: bookmark, options: [.withoutUI, .withoutMounting],
                                      relativeTo: nil, bookmarkDataIsStale: &stale),
                   FileManager.default.fileExists(atPath: url.path) {
                    urls[item.id] = url
                    if stale || url.path != path,
                       let fresh = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
                        var updated = item
                        updated.location = .linked(bookmark: fresh, path: url.path)
                        updated.name = url.lastPathComponent
                        refreshed.append(updated)
                    }
                } else if FileManager.default.fileExists(atPath: path) {
                    urls[item.id] = URL(filePath: path)
                }
            }
        }
        return (urls, refreshed)
    }

    // MARK: Removing

    /// Deletes the copies the Tray owns. Linked files are never touched.
    @concurrent
    func deleteOwned(_ items: [TrayItem]) async {
        deleteOwnedNow(items)
    }

    /// Synchronous variant for `applicationWillTerminate` (Clear on quit).
    func deleteOwnedNow(_ items: [TrayItem]) {
        for item in items where item.isOwned {
            let folder = root.appending(path: item.id.uuidString, directoryHint: .isDirectory)
            do { try FileManager.default.removeItem(at: folder) } catch {
                log.error("could not delete a tray copy: \(TrayLogCode.of(error), privacy: .public) \(error.localizedDescription, privacy: .private)")
            }
        }
    }

    /// Removes `<uuid>` folders that the index does not list (left behind by a crash during a copy). Only call this
    /// with an index that was read successfully: without one, `recoverCopies` finds the copies again instead.
    @concurrent
    func removeOrphans(keeping items: [TrayItem]) async {
        let known = Set(items.filter(\.isOwned).map(\.id.uuidString))
        for folder in copyFolders() where !known.contains(folder.lastPathComponent) {
            try? FileManager.default.removeItem(at: folder)
        }
    }

    /// Rebuilds the owned items from the `<uuid>/<name>` folders (the index is missing or unreadable), newest first.
    /// Links cannot be recovered (their bookmarks were only in the index); the user's files are untouched anyway.
    /// Folders with no finished copy in them (a crash mid-copy) are removed.
    @concurrent
    func recoverCopies(now: Date) async -> [TrayItem] {
        var items: [TrayItem] = []
        for folder in copyFolders() {
            guard let id = UUID(uuidString: folder.lastPathComponent) else { continue }
            let names = ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
                .filter { !$0.hasPrefix(Self.stagingPrefix) && $0 != ".DS_Store" }.sorted()
            guard let name = names.first else {
                try? FileManager.default.removeItem(at: folder)
                continue
            }
            let file = folder.appending(path: name, directoryHint: .inferFromPath)
            let created = (try? folder.resourceValues(forKeys: [.creationDateKey]))?.creationDate
            items.append(TrayItem(id: id, name: name, location: .owned(path: "\(id.uuidString)/\(name)"),
                                  size: Self.size(of: file), addedAt: min(created ?? now, now),
                                  typeIdentifier: TrayItem.contentType(of: file).identifier, originalPath: nil))
        }
        return items.sorted { $0.addedAt > $1.addedAt }
    }

    /// The `<uuid>` folders in the Tray folder.
    private func copyFolders() -> [URL] {
        let entries = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        return entries.filter { UUID(uuidString: $0.lastPathComponent) != nil }
    }

    // MARK: Index

    /// Reads `index.json`. A file that cannot be decoded is moved aside (`index.json.corrupt-<time>`, kept for
    /// diagnosis) and reported as `.unreadable`, so the caller rebuilds instead of trusting an empty list.
    @concurrent
    func readIndex() async -> TrayIndexRead {
        guard FileManager.default.fileExists(atPath: indexURL.path) else { return .missing }
        do {
            return .loaded(try JSONDecoder().decode(TrayIndex.self, from: Data(contentsOf: indexURL)))
        } catch {
            let aside = indexURL.appendingPathExtension("corrupt-\(Int(Date().timeIntervalSince1970))")
            try? FileManager.default.moveItem(at: indexURL, to: aside)
            log.error("unreadable tray index, rebuilding it from the kept copies: \(TrayLogCode.of(error), privacy: .public)")
            return .unreadable
        }
    }

    /// Writes the index right away (terminate hook; everything else goes through `JSONFileStore`).
    func writeIndexNow(_ index: TrayIndex) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try encoder.encode(index).write(to: indexURL, options: .atomic)
        } catch {
            log.error("could not write the tray index: \(TrayLogCode.of(error), privacy: .public) \(error.localizedDescription, privacy: .private)")
        }
    }

    // MARK: Sizes

    /// Logical size in bytes; folders are summed.
    static func size(of url: URL) -> Int64 { FileFingerprint.of(url).size }
}
