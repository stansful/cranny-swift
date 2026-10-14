// CrannyAppShell/Overlay/DragDetector.swift — notices file drags from any app (ARCHITECTURE.md §5.5, R1 §5.1).
// On mouse drags near a panel (the coordinator says which: within some panel's drag zone) it reads the drag
// pasteboard's `changeCount`; when it changes it inspects the `types` for file URLs or file promises. A file drag acts
// only where it enters a drag zone, so a drag elsewhere (selecting text, moving a window, a slider) costs no
// pasteboard query per event: one `changeCount` read when it ends keeps the baseline, so what it wrote is never taken
// for a later drag's. Reading the drag pasteboard never shows the macOS 15.4+ paste alert (only `.general` asks).
// Every drag bumps the count (text, tabs…), so the types decide. No timers: mouse events drive it.
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
    /// A mouse button is down and the pointer moved since the last up or move (a drag, inspected or not).
    private var sawDrag = false

    init(pasteboard: NSPasteboard = NSPasteboard(name: .drag)) {
        self.pasteboard = pasteboard
        lastChangeCount = pasteboard.changeCount
    }

    /// Feeds a pointer event; returns the new drag state when it changed (`.some(nil)` = the drag ended).
    /// `nearPanel`: the pointer is within some panel's drag zone (`HoverZones.dragZone`), where a file drag acts.
    func update(_ kind: PointerMonitor.Kind, nearPanel: Bool) -> Contents?? {
        switch kind {
        case .dragged:
            sawDrag = true
            guard !inspected, nearPanel else { return nil }                    // one drag session per mouse-down
            let count = pasteboard.changeCount
            guard count != lastChangeCount else { return nil }               // the source has not written it yet
            lastChangeCount = count
            inspected = true
            let contents = Self.contents(types: pasteboard.types ?? [], pasteboard: pasteboard)
            guard contents.hasFiles else { return nil }
            current = contents
            return .some(contents)
        case .up, .moved:
            // A drag that never came near a panel was not inspected: what its source wrote joins the baseline now,
            // once, so the next drag near a panel is judged by its own write.
            if sawDrag && !inspected { lastChangeCount = pasteboard.changeCount }
            // A plain move means the button is up again: the drag is over even if the up event was missed.
            sawDrag = false
            inspected = false
            guard current != nil else { return nil }
            current = nil
            return .some(nil)
        }
    }

    /// The drag ended through our own drop destination (the global up event may follow, or not). The next up or
    /// move still settles the baseline.
    func reset() {
        current = nil
        inspected = false
    }

    // MARK: Paused pointer (OverlayCoordinator+Pointer)

    /// A mouse button went down while pointer events were paused (no drag in progress when they paused): every drag
    /// before it is over, so what they wrote joins the baseline, as their ends would have done.
    func pressedWhilePaused() {
        lastChangeCount = pasteboard.changeCount
    }

    /// Pointer events resume. With every button up, the drags made meanwhile are over: the baseline takes what they
    /// wrote. With a button down, a drag is in progress; its press set the baseline (`pressedWhilePaused`), and its end
    /// settles it like any drag's.
    func resumed(buttonsDown: Bool) {
        if buttonsDown { sawDrag = true } else { lastChangeCount = pasteboard.changeCount }
    }

    // MARK: Pasteboard

    /// The pasteboard types of file promises (built once, not per drag update).
    static let promiseTypes = Set(NSFilePromiseReceiver.readableDraggedTypes)

    /// File URLs or file promises (Photos, Mail, Safari images) make a file drag.
    static func contents(types: [NSPasteboard.PasteboardType], pasteboard: NSPasteboard?) -> Contents {
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
