// CrannyTray/Store/TrayItem.swift — one file kept in the Tray, and the on-disk index (`tray/index.json`,
// ARCHITECTURE.md §7.8). Persisted: never rename a property or a case.
import Foundation
import UniformTypeIdentifiers

/// A file or folder in the Tray. Either the Tray owns a copy (`owned`) or it points at the user's file (`linked`).
nonisolated struct TrayItem: Codable, Hashable, Sendable, Identifiable {
    /// Where the bytes are.
    enum Location: Codable, Hashable, Sendable {
        /// A copy inside the Tray folder; `path` is relative to it ("<uuid>/<name>"). Removing the item deletes it.
        case owned(path: String)
        /// The user's own file (link mode, pipeline results). Removing the item never touches the file.
        /// `path` is the last known location, used when the bookmark cannot be resolved.
        case linked(bookmark: Data, path: String)
    }

    var id: UUID
    /// The file name shown under the tile ("Brief.pdf").
    var name: String
    var location: Location
    /// Bytes (logical size; folders are summed).
    var size: Int64
    var addedAt: Date
    /// `UTType` identifier ("public.png", "public.folder"); nil if unknown.
    var typeIdentifier: String?
    /// Where the file was dropped from: avoids keeping the same file twice.
    var originalPath: String?
    /// The original's latest modification when it was copied (folders: the newest file inside). A copy is only reused
    /// for a repeat drop while the original still has this date and `size`; an edited original is copied again.
    /// nil for links, recovered copies and indexes written before this field existed.
    var originalModified: Date? = nil

    var contentType: UTType { typeIdentifier.flatMap(UTType.init) ?? .item }
    var isOwned: Bool { if case .owned = location { true } else { false } }
    /// The last known location of a linked file (owned copies resolve through `TrayStorage.ownedURL`).
    var linkedURL: URL? { if case .linked(_, let path) = location { URL(filePath: path) } else { nil } }
    /// "Brief" for "Brief.pdf" (output names).
    var baseName: String { (name as NSString).deletingPathExtension }
}

/// The JSON document at `tray/index.json`, newest item first.
nonisolated struct TrayIndex: Codable, Equatable, Sendable {
    var version = 1
    var items: [TrayItem] = []
}

extension TrayItem {
    /// The content type of a file on disk (directories → `.folder`, unknown → by extension).
    nonisolated static func contentType(of url: URL) -> UTType {
        if let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType { return type }
        return UTType(filenameExtension: url.pathExtension) ?? .item
    }
}

/// Size and latest modification of a file or folder, read in one pass (folders: summed / the newest file inside).
/// Tells whether a file dropped again is still the one the Tray copied.
nonisolated struct FileFingerprint: Equatable, Sendable {
    /// Logical bytes.
    var size: Int64
    var modified: Date?

    static func of(_ url: URL) -> FileFingerprint {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .fileSizeKey, .totalFileSizeKey, .contentModificationDateKey]
        var url = url
        url.removeAllCachedResourceValues()             // a URL caches what it read: a repeat drop must see the edit
        guard let values = try? url.resourceValues(forKeys: keys) else { return FileFingerprint(size: 0, modified: nil) }
        guard values.isDirectory == true else {
            return FileFingerprint(size: Int64(values.totalFileSize ?? values.fileSize ?? 0), modified: values.contentModificationDate)
        }
        var total: Int64 = 0
        var newest = values.contentModificationDate
        let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: Array(keys))
        while let child = enumerator?.nextObject() as? URL {
            guard let v = try? child.resourceValues(forKeys: keys) else { continue }
            if let date = v.contentModificationDate, newest.map({ date > $0 }) ?? true { newest = date }
            if v.isDirectory != true { total += Int64(v.totalFileSize ?? v.fileSize ?? 0) }
        }
        return FileFingerprint(size: total, modified: newest)
    }

    /// True while `item` (an owned copy) still matches the original it was copied from.
    func matches(_ item: TrayItem) -> Bool {
        guard let kept = item.originalModified, let modified else { return false }
        return size == item.size && abs(modified.timeIntervalSince(kept)) < 0.001
    }
}

/// Matching a dropped file against the Tray (no duplicates).
nonisolated enum TrayDedup {
    /// The item that already holds `url` (by its original path or link path). For an owned copy the caller still
    /// checks that the original has not changed since (`FileFingerprint.matches`).
    static func match(_ url: URL, in items: [TrayItem]) -> TrayItem? {
        let path = url.standardizedFileURL.path
        return items.first { item in
            if item.originalPath == path { return true }
            if case .linked(_, let linked) = item.location { return linked == path }
            return false
        }
    }
}
