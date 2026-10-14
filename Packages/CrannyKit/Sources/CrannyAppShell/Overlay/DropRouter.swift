// CrannyAppShell/Overlay/DropRouter.swift — drops on one panel (ARCHITECTURE.md §5.6): the drag location goes to
// the canvas's `NotchZones` (they arm by geometry; the innermost accepting zone wins), a drop reads file URLs,
// resolves file promises into the tray's Incoming folder, then `zones.performDrop(fallback: .trayKeep)`; if no
// zone took it, `services.tray.accept` keeps it, so a file is never lost.
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

    init(scene: NotchSceneModel, viewModel: NotchViewModel, registry: ModuleRegistry) {
        self.scene = scene; self.viewModel = viewModel; self.registry = registry
    }

    // MARK: NotchDropTarget

    func dragUpdated(_ info: any NSDraggingInfo, in view: NSView) -> NSDragOperation {
        let contents = DragDetector.contents(types: info.draggingPasteboard.types ?? [], pasteboard: info.draggingPasteboard)
        guard contents.hasFiles else { return [] }
        // The detector normally saw it first; a drag that started over the panel (or a missed event) starts here.
        if viewModel.state.fileDrag == nil { viewModel.send(.fileDragEntered(contents.types)) }
        scene.zones.dragUpdated(at: Self.canvasPoint(info.draggingLocation, in: view), types: contents.types)
        return .copy
    }

    func dragExited() {
        scene.zones.dragEnded()
    }

    func performDrop(_ info: any NSDraggingInfo, in view: NSView) -> Bool {
        let pasteboard = info.draggingPasteboard
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        let promises = pasteboard.readObjects(forClasses: [NSFilePromiseReceiver.self]) as? [NSFilePromiseReceiver] ?? []
        let tray = registry.services.tray
        defer { onDropFinished() }
        // Nobody can take it: no armed zone and no Tray to keep it. Refuse, so the source keeps its file.
        guard !(urls.isEmpty && promises.isEmpty), scene.zones.armedDropZone != nil || tray != nil else {
            scene.zones.dragEnded()
            viewModel.send(.filesDropped(count: 0))
            return false
        }
        let count = urls.count + promises.reduce(0) { $0 + max($1.fileTypes.count, 1) }
        viewModel.send(.filesDropped(count: count))                        // haptic, gulp and "Pop" right away
        let zones = scene.zones, paths = registry.services.paths
        Task {
            var files = urls
            if !promises.isEmpty, let directory = FilePromiseResolver.incomingDirectory(paths: paths) {
                files += await FilePromiseResolver.resolve(promises, into: directory)
            }
            guard !files.isEmpty else { zones.dragEnded(); return }
            let payload = DropPayload(fileURLs: files, contentTypes: DragDetector.unique(files.map(DragDetector.contentType(of:))))
            if await zones.performDrop(payload, fallback: .trayKeep) { return }
            if let tray, await tray.accept(payload) { return }
            log.error("drop of \(files.count, privacy: .public) file(s) was not taken")
        }
        return true
    }

    /// `draggingLocation` (window coordinates, bottom-left origin) → the canvas's top-left coordinates.
    static func canvasPoint(_ location: CGPoint, in view: NSView) -> CGPoint {
        let local = view.convert(location, from: nil)
        return CGPoint(x: local.x, y: view.bounds.height - local.y)
    }
}
