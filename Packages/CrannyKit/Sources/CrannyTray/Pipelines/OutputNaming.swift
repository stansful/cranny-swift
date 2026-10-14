// CrannyTray/Pipelines/OutputNaming.swift — how pipeline results are named and where they are written
// (DESIGN.md §8.2 "Result": next to the source, or Downloads for files the Tray owns). Names are derived from the
// input so chains compose ("hero" → "hero 800×450.png" → "hero 800×450.jpg") and the editor can preview them.
import Foundation

/// The words that go into result names, localized once on the main actor and passed to the background runner.
nonisolated struct OutputNaming: Sendable, Equatable {
    var compressed: String          // "compressed" → "photo (compressed).jpg"
    var noBackground: String        // "no background"
    var noMetadata: String          // "no metadata"
    var archive: String             // "Archive" → "Archive 2026-10-14.zip"

    static let english = OutputNaming(compressed: "compressed", noBackground: "no background",
                                      noMetadata: "no metadata", archive: "Archive")

    static var localized: OutputNaming {
        OutputNaming(
            compressed: String(localized: "compressed", bundle: .module, comment: "Tray pipelines: suffix of a compressed file's name, \"photo (compressed).jpg\""),
            noBackground: String(localized: "no background", bundle: .module, comment: "Tray pipelines: suffix of a file's name after Remove background, \"photo (no background).png\""),
            noMetadata: String(localized: "no metadata", bundle: .module, comment: "Tray pipelines: suffix of a file's name after Strip metadata, \"photo (no metadata).jpg\""),
            archive: String(localized: "Archive", bundle: .module, comment: "Tray pipelines: base name of a dated zip archive, \"Archive 2026-10-14.zip\""))
    }

    // MARK: Names (base names, without extension)

    func compressed(_ base: String) -> String { "\(base) (\(compressed))" }
    func withoutBackground(_ base: String) -> String { "\(base) (\(noBackground))" }
    func withoutMetadata(_ base: String) -> String { "\(base) (\(noMetadata))" }
    /// "hero 1600×900" (pixel size, language-neutral).
    func resized(_ base: String, width: Int, height: Int) -> String { "\(base) \(width)×\(height)" }

    /// The archive's base name for `naming`: the first item's base name or "Archive 2026-10-14" (local date).
    func zipBaseName(firstItem: String, naming: TrayZipNaming, date: Date, timeZone: TimeZone = .current) -> String {
        switch naming {
        case .firstItem:
            return firstItem.isEmpty ? archive : firstItem
        case .dated:
            let day = date.formatted(Date.ISO8601FormatStyle(dateSeparator: .dash, timeZone: timeZone).year().month().day())
            return "\(archive) \(day)"
        }
    }

    // MARK: Uniqueness (Finder style: "name 2.ext", "name 3.ext")

    /// `name.ext`, or the first "name N.ext" not in `taken` (case-insensitive, like APFS by default).
    static func unique(base: String, ext: String, taken: Set<String>) -> String {
        let lower = Set(taken.map { $0.lowercased() })
        func file(_ b: String) -> String { ext.isEmpty ? b : "\(b).\(ext)" }
        if !lower.contains(file(base).lowercased()) { return file(base) }
        var n = 2
        while lower.contains(file("\(base) \(n)").lowercased()) { n += 1 }
        return file("\(base) \(n)")
    }

    /// A URL in `directory` that does not exist yet.
    static func uniqueURL(base: String, ext: String, in directory: URL) -> URL {
        let taken = Set((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? [])
        return directory.appending(path: unique(base: base, ext: ext, taken: taken), directoryHint: .notDirectory)
    }
}

/// Where results of a run are written.
nonisolated struct OutputPlacement: Sendable, Equatable {
    /// The Tray's own folder (results of tray-owned files go to `downloads` instead).
    var trayRoot: URL
    /// Folders whose files are temporary (resolved file promises, `NSTemporaryDirectory`): never write next to them.
    var temporaryRoots: [URL]
    var downloads: URL

    /// The folder for the results of a run whose first source is `source`.
    func directory(for source: URL?, location: TrayOutputLocation) -> URL {
        guard location == .nextToSource, let source else { return downloads }
        let folder = source.deletingLastPathComponent()
        if ([trayRoot] + temporaryRoots).contains(where: { Self.isInside(source, $0) }) { return downloads }
        return FileManager.default.isWritableFile(atPath: folder.path) ? folder : downloads
    }

    /// True when `url` is `root` or inside it (symlinks resolved: /var → /private/var).
    static func isInside(_ url: URL, _ root: URL) -> Bool {
        let path = url.standardizedFileURL.resolvingSymlinksInPath().path
        let rootPath = root.standardizedFileURL.resolvingSymlinksInPath().path
        return path == rootPath || path.hasPrefix(rootPath.hasSuffix("/") ? rootPath : rootPath + "/")
    }
}
