// CrannyTray/Store/TrayStorage.swift — the Tray's files on disk (ARCHITECTURE.md §7.8): copies under
// `AppPaths.directory(for: .tray)/<uuid>/<name>`, plain (non-sandboxed) bookmarks for links, the JSON index.
// All file work is `@concurrent` (never on the main actor, §9.2). Only items the Tray OWNS are ever deleted.
import CrannyCore
import Foundation
import os
import UniformTypeIdentifiers

private nonisolated let log = Log.logger(.tray)

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

    /// Keeps each of `urls` (copy, or link in `.link` mode unless temporary). Files that fail are skipped and logged;
    /// the result is in input order.
    @concurrent
    func ingest(_ urls: [URL], mode: TrayStorageMode, now: Date) async -> [TrayItem] {
        var items: [TrayItem] = []
        for url in urls {
            if Task.isCancelled { break }
            do {
                let copies = mode == .copy || isTemporary(url)
                items.append(try copies ? copy(url, now: now) : link(url, now: now))
            } catch {
                log.error("could not keep \(url.lastPathComponent, privacy: .private): \(error.localizedDescription, privacy: .public)")
            }
        }
        return items
    }

    /// Items that point at files Cranny wrote elsewhere (pipeline results).
    @concurrent
    func linkResults(_ urls: [URL], now: Date) async -> [TrayItem] {
        urls.compactMap { try? link($0, now: now) }
    }

    private func copy(_ source: URL, now: Date) throws -> TrayItem {
        let id = UUID()
        let name = source.lastPathComponent
        let folder = root.appending(path: id.uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let destination = folder.appending(path: name, directoryHint: .inferFromPath)
        do {
            try FileManager.default.copyItem(at: source, to: destination)   // APFS clone when possible
        } catch {
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
        return TrayItem(id: id, name: name, location: .owned(path: "\(id.uuidString)/\(name)"),
                        size: Self.size(of: destination), addedAt: now,
                        typeIdentifier: TrayItem.contentType(of: destination).identifier,
                        originalPath: isTemporary(source) ? nil : source.standardizedFileURL.path)
    }

    private func link(_ url: URL, now: Date) throws -> TrayItem {
        let bookmark = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        let path = url.standardizedFileURL.path
        return TrayItem(id: UUID(), name: url.lastPathComponent, location: .linked(bookmark: bookmark, path: path),
                        size: Self.size(of: url), addedAt: now, typeIdentifier: TrayItem.contentType(of: url).identifier,
                        originalPath: path)
    }

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
                log.error("could not delete a tray copy: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Removes `<uuid>` folders that no index entry refers to (left behind by a crash during a copy).
    @concurrent
    func removeOrphans(keeping items: [TrayItem]) async {
        let known = Set(items.filter(\.isOwned).map(\.id.uuidString))
        let entries = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        for entry in entries where UUID(uuidString: entry.lastPathComponent) != nil && !known.contains(entry.lastPathComponent) {
            try? FileManager.default.removeItem(at: entry)
        }
    }

    // MARK: Index

    /// Writes the index right away (terminate hook; everything else goes through `JSONFileStore`).
    func writeIndexNow(_ index: TrayIndex) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try encoder.encode(index).write(to: indexURL, options: .atomic)
        } catch {
            log.error("could not write the tray index: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: Sizes

    /// Logical size in bytes; folders are summed.
    static func size(of url: URL) -> Int64 {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .fileSizeKey, .totalFileSizeKey]
        guard let values = try? url.resourceValues(forKeys: keys) else { return 0 }
        guard values.isDirectory == true else { return Int64(values.totalFileSize ?? values.fileSize ?? 0) }
        var total: Int64 = 0
        let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: Array(keys))
        while let child = enumerator?.nextObject() as? URL {
            if let v = try? child.resourceValues(forKeys: keys), v.isDirectory != true {
                total += Int64(v.totalFileSize ?? v.fileSize ?? 0)
            }
        }
        return total
    }
}
