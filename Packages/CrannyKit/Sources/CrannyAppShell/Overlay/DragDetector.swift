// CrannyAppShell/Overlay/DragDetector.swift — notices file drags from any app (ARCHITECTURE.md §5.5, R1 §5.1).
// On mouse drags it reads the drag pasteboard's `changeCount`; when it changes it inspects the `types` for file
// URLs or file promises. Reading the drag pasteboard never shows the macOS 15.4+ paste alert (only `.general`
// asks). Every drag bumps the count (text, tabs…), so the types decide. No timers: mouse events drive it.
import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor final class DragDetector {
    /// What the drag pasteboard holds, as far as the notch cares.
    nonisolated struct Contents: Equatable, Sendable {
        var hasFiles: Bool
        /// The dragged files' content types (file URLs by extension, promises by their declared types).
        var types: [UTType]
    }

    /// The file drag in progress (nil = none).
    private(set) var current: Contents?
    private let pasteboard: NSPasteboard
    private var lastChangeCount: Int
    /// The pasteboard was inspected for this mouse-down already (a drag session writes it once).
    private var inspected = false

    init(pasteboard: NSPasteboard = NSPasteboard(name: .drag)) {
        self.pasteboard = pasteboard
        lastChangeCount = pasteboard.changeCount
    }

    /// Feeds a pointer event; returns the new drag state when it changed (`.some(nil)` = the drag ended).
    func update(_ kind: PointerMonitor.Kind) -> Contents?? {
        switch kind {
        case .dragged:
            guard !inspected else { return nil }                                // one drag session per mouse-down
            let count = pasteboard.changeCount
            guard count != lastChangeCount else { return nil }               // the source has not written it yet
            lastChangeCount = count
            inspected = true
            let contents = Self.contents(types: pasteboard.types ?? [], pasteboard: pasteboard)
            guard contents.hasFiles else { return nil }
            current = contents
            return .some(contents)
        case .up, .moved:
            // A plain move means the button is up again: the drag is over even if the up event was missed.
            inspected = false
            guard current != nil else { return nil }
            current = nil
            return .some(nil)
        }
    }

    /// The drag ended through our own drop destination (the global up event may follow, or not).
    func reset() {
        current = nil
        inspected = false
    }

    // MARK: Pasteboard

    /// File URLs or file promises (Photos, Mail, Safari images) make a file drag.
    static func contents(types: [NSPasteboard.PasteboardType], pasteboard: NSPasteboard?) -> Contents {
        let promiseTypes = Set(NSFilePromiseReceiver.readableDraggedTypes)
        let hasURLs = types.contains(.fileURL)
        let hasPromises = types.contains { promiseTypes.contains($0.rawValue) }
        guard hasURLs || hasPromises else { return Contents(hasFiles: false, types: []) }
        var utTypes: [UTType] = []
        if hasURLs, let urls = pasteboard?.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] {
            utTypes += urls.map(Self.contentType(of:))
        }
        if hasPromises, let receivers = pasteboard?.readObjects(forClasses: [NSFilePromiseReceiver.self]) as? [NSFilePromiseReceiver] {
            utTypes += receivers.flatMap(\.fileTypes).compactMap { UTType($0) }
        }
        if utTypes.isEmpty { utTypes = [.item] }
        return Contents(hasFiles: true, types: Self.unique(utTypes))
    }

    /// By extension only: no file I/O on the main actor (§9.2). Folders are `.folder`.
    nonisolated static func contentType(of url: URL) -> UTType {
        if url.hasDirectoryPath { return .folder }
        guard !url.pathExtension.isEmpty else { return .data }
        return UTType(filenameExtension: url.pathExtension) ?? .data
    }

    nonisolated static func unique(_ types: [UTType]) -> [UTType] {
        var seen = Set<UTType>()
        return types.filter { seen.insert($0).inserted }
    }
}
