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
