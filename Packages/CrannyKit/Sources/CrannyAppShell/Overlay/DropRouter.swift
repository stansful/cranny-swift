// CrannyAppShell/Overlay/DropRouter.swift — drops on one panel (ARCHITECTURE.md §5.6): the drag location goes to
// the canvas's `NotchZones` (they arm by geometry; the innermost accepting zone wins), a drop reads file URLs,
// resolves file promises into the tray's Incoming folder, then `zones.performDrop(fallback: .trayKeep)`; if no
// zone took it, `services.tray.accept` keeps it, so a file is never lost.
//
// The zone that takes a drop is the one armed under the pointer when the drop happened. `performDrop` picks it
// when it is called, so the zone's view must still be on screen then. File promises resolve asynchronously
// (Photos exports first), so while they do, the `drop` hold keeps the panel in its state (catch or grid): the gulp
// and the return wait until the payload has been handed to the zone. Under that hold the Incoming folder is created
// and the files' types are looked up off the main actor; a drop of plain file URLs (no hold) takes the types its drag
// already found.
//
// The dragged contents are read from the pasteboard once per dragging session (`draggingSequenceNumber`), not with
// every pointer move over the panel: a session's pasteboard does not change.
//
// Drags that start in Cranny itself (a Tray tile dragged out across its own panel) are never taken: the Tray offers
// no operation inside the app, and treating them as file drags would leave the machine in a drag that no detector
// ever ends (`DragDetector` sees no events of our own drag session). A drag this router started the machine's drag
// state for, and that ends without a drop here, ends it again (`draggingEnded`).
import AppKit
import CrannyCore
import CrannyNotchUI
import Foundation
import UniformTypeIdentifiers
import os

private let log = Log.logger(.overlay)

@MainActor final class DropRouter: NotchDropTarget {
    private let scene: NotchSceneModel
    private let viewModel: NotchViewModel
    private let registry: ModuleRegistry
    /// The drop finished (the coordinator's `DragDetector` may never see the source's mouse-up).
    var onDropFinished: () -> Void = {}
    /// How long to wait for a file promise (tests shorten it).
    var promiseTimeout: Duration = FilePromiseResolver.timeout
    /// This router (not the coordinator's drag detector) put the machine into its drag state, so it ends it too.
    private var startedDragState = false
    /// The dragging session whose contents were read, and whether its pasteboard declared file URLs only (no promises).
    private var session: (sequence: Int, contents: DragDetector.Contents, urlsOnly: Bool)?

    init(scene: NotchSceneModel, viewModel: NotchViewModel, registry: ModuleRegistry) {
        self.scene = scene; self.viewModel = viewModel; self.registry = registry
    }

    // MARK: NotchDropTarget

    func dragUpdated(_ info: any NSDraggingInfo, in view: NSView) -> NSDragOperation {
        guard Self.accepts(source: info.draggingSource, operations: info.draggingSourceOperationMask) else { return [] }
        let contents = sessionContents(info).contents
        guard contents.hasFiles else { return [] }
        // The detector normally saw it first; a drag that started over the panel (or a missed event) starts here.
        if viewModel.state.fileDrag == nil {
            startedDragState = true
            viewModel.send(.fileDragEntered(contents.types))
        }
        let armed = scene.zones.armedDropZone
        scene.zones.dragUpdated(at: Self.canvasPoint(info.draggingLocation, in: view), types: contents.types)
        // DESIGN.md §8.3, §14.2: a zone arming under the pointer is felt (its highlight is NotchUI's).
        if let now = scene.zones.armedDropZone, now != armed { registry.services.haptics.play(.alignment) }
        return .copy
    }

    func dragExited() {
        scene.zones.dragEnded()
    }

    /// AppKit ends the session (dropped here, elsewhere or cancelled). A drag whose drag state this router started
    /// and that was not dropped here leaves it now, also when the panel closed meanwhile (the machine dropped its
    /// drag state then, the armed zones did not); the detector's own drags end through the detector. A drop here
    /// cleared `startedDragState` already (`performDrop`).
    func dragEnded() {
        session = nil
        guard startedDragState else { return }
        startedDragState = false
        scene.zones.dragEnded()
        viewModel.send(.fileDragEnded)                                          // a no-op once the drag state is gone
    }

    /// Only drags from other apps are file drags for the notch. `source` is non-nil for a drag that started in Cranny;
    /// an empty mask means the source allows no operation here (the Tray offers none inside the app).
    static func accepts(source: Any?, operations: NSDragOperation) -> Bool {
        source == nil && !operations.isEmpty
    }

    func performDrop(_ info: any NSDraggingInfo, in view: NSView) -> Bool {
        guard Self.accepts(source: info.draggingSource, operations: info.draggingSourceOperationMask) else { return false }
        startedDragState = false
        let pasteboard = info.draggingPasteboard
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        let promises = pasteboard.readObjects(forClasses: [NSFilePromiseReceiver.self]) as? [NSFilePromiseReceiver] ?? []
        // Arm by the drop location itself: the source's mouse-up may reach the pointer monitor first and end the
        // drag (clearing the armed zone) before AppKit delivers the drop.
        let read = sessionContents(info)
        session = nil
        scene.zones.dragUpdated(at: Self.canvasPoint(info.draggingLocation, in: view), types: read.contents.types)
        // File URLs alone: the contents' types are exactly these URLs' (the same read, the same mapping).
        return drop(urls: urls, promises: promises, types: read.urlsOnly && promises.isEmpty ? read.contents.types : nil)
    }

    /// The session's dragged contents, read from its pasteboard on the session's first update only.
    private func sessionContents(_ info: any NSDraggingInfo) -> (contents: DragDetector.Contents, urlsOnly: Bool) {
        if let session, session.sequence == info.draggingSequenceNumber { return (session.contents, session.urlsOnly) }
        let pasteboard = info.draggingPasteboard
        let types = pasteboard.types ?? []
        let contents = DragDetector.contents(types: types, pasteboard: pasteboard)
        let urlsOnly = types.contains(.fileURL) && !types.contains { DragDetector.promiseTypes.contains($0.rawValue) }
        session = (info.draggingSequenceNumber, contents, urlsOnly)
        return (contents, urlsOnly)
    }

    // MARK: Delivery

    /// Takes the dropped files: feedback now, delivery to the armed zone (else `.trayKeep`, else the Tray) once
    /// every promise has resolved. Returns false (the source keeps its files) when nobody could take them. `types`:
    /// the content types of `urls` when the caller has them already (nil: looked up here); a drop with promises looks
    /// up every file's once they have arrived.
    @discardableResult func drop(urls: [URL], promises: [NSFilePromiseReceiver], types: [UTType]? = nil) -> Bool {
        let tray = registry.services.tray
        defer { onDropFinished() }
        // Nobody can take it: no armed zone and no Tray to keep it. Refuse, so the source keeps its file.
        guard !(urls.isEmpty && promises.isEmpty), scene.zones.armedDropZone != nil || tray != nil else {
            scene.zones.dragEnded()
            viewModel.send(.filesDropped(count: 0))
            return false
        }
        let count = urls.count + promises.reduce(0) { $0 + max($1.fileTypes.count, 1) }
        let waits = !promises.isEmpty
        // The panel (and with it the armed zone's view) stays until the payload is handed over.
        if waits { viewModel.send(.hold(NotchMachineState.dropHold, true)) }
        viewModel.send(.filesDropped(count: count))                        // haptic, gulp and "Pop" right away
        let zones = scene.zones, paths = registry.services.paths, timeout = promiseTimeout
        let viewModel = viewModel
        Task {
            var files = urls
            var types = types
            var incoming: URL?
            if waits {
                // Still under the `drop` hold: the folder (file I/O) and the types (a lookup per file) off the main actor.
                incoming = await FilePromiseResolver.makeIncomingDirectory(paths: paths)
                if let incoming {
                    files += await FilePromiseResolver.resolve(promises, into: incoming, timeout: timeout)
                }
                types = await Self.contentTypes(of: files)
                // Released on the main actor's next turn: `performDrop` below picks its zone synchronously, before
                // its first suspension, so the zone is chosen while the panel is still held.
                Task { viewModel.send(.hold(NotchMachineState.dropHold, false)) }
            }
            await Self.deliver(files, types: types, zones: zones, tray: tray)
            // Every taker copied or staged the files inside the awaited call (Tray keep, drop pipelines, AirDrop),
            // and a drop nobody took is gone anyway: the promised copies must not outlive the drop.
            if let incoming { await FilePromiseResolver.discard(incoming) }
        }
        return true
    }

    /// The files' content types, by extension (`DragDetector.contentType(of:)`), off the main actor.
    @concurrent private nonisolated static func contentTypes(of files: [URL]) async -> [UTType] {
        DragDetector.unique(files.map(DragDetector.contentType(of:)))
    }

    /// Hands `files` (of `types`; nil: looked up now) to the armed zone (else `.trayKeep`), else to the Tray.
    private static func deliver(_ files: [URL], types: [UTType]?, zones: NotchZones, tray: (any TrayIntake)?) async {
        guard !files.isEmpty else { zones.dragEnded(); return }
        let types = types ?? DragDetector.unique(files.map(DragDetector.contentType(of:)))
        let payload = DropPayload(fileURLs: files, contentTypes: types)
        if await zones.performDrop(payload, fallback: .trayKeep) { return }
        if let tray, await tray.accept(payload) { return }
        log.error("drop of \(files.count, privacy: .public) file(s) was not taken")
    }

    /// `draggingLocation` (window coordinates, bottom-left origin) → the canvas's top-left coordinates.
    static func canvasPoint(_ location: CGPoint, in view: NSView) -> CGPoint {
        let local = view.convert(location, from: nil)
        return CGPoint(x: local.x, y: view.bounds.height - local.y)
    }
}
