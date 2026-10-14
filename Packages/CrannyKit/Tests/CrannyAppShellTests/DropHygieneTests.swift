// What drops leave behind (ARCHITECTURE.md §5.5–§5.6): a drag that starts in Cranny (a Tray tile dragged out across
// its own panel) never becomes a file drag of the machine, a drag the router started ends with its session, and the
// files a promise drop wrote into `<caches>/tray/Incoming` are deleted once the drop is delivered. No windows: a fake
// `NSDraggingInfo` on a private pasteboard, promises written by a fake receiver.
import AppKit
@testable import CrannyCore
import CrannyNotchUI
import Foundation
import Testing
import UniformTypeIdentifiers
@testable import CrannyAppShell

/// The parts of a dragging session the router reads.
private final class FakeDraggingInfo: NSObject, NSDraggingInfo {
    let draggingPasteboard: NSPasteboard
    let draggingSource: Any?
    let draggingSourceOperationMask: NSDragOperation
    let draggingLocation = NSPoint(x: 50, y: 150)

    init(pasteboard: NSPasteboard, source: Any?, operations: NSDragOperation) {
        draggingPasteboard = pasteboard; draggingSource = source; draggingSourceOperationMask = operations
    }

    var draggingDestinationWindow: NSWindow? { nil }
    var draggedImageLocation: NSPoint { .zero }
    var draggedImage: NSImage? { nil }
    var draggingSequenceNumber: Int { 1 }
    func slideDraggedImage(to screenPoint: NSPoint) {}
    var draggingFormation: NSDraggingFormation = .default
    var animatesToDestination = false
    var numberOfValidItemsForDrop = 1
    func enumerateDraggingItems(options enumOpts: NSDraggingItemEnumerationOptions = [], for view: NSView?, classes classArray: [AnyClass],
                                searchOptions: [NSPasteboard.ReadingOptionKey: Any] = [:],
                                using block: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void) {}
    var springLoadingHighlight: NSSpringLoadingHighlight { .none }
    func resetSpringLoading() {}
}

/// A private drag pasteboard holding one file URL.
private func filePasteboard() -> NSPasteboard {
    let pasteboard = NSPasteboard(name: NSPasteboard.Name("cranny.test.\(UUID().uuidString)"))
    pasteboard.clearContents()
    pasteboard.writeObjects([URL(fileURLWithPath: "/tmp/cranny-test-report.pdf") as NSURL])
    return pasteboard
}

@MainActor private func makeRouter() -> (DropRouter, NotchViewModel, NotchSceneModel, ModuleRegistry) {
    let registry = ModuleRegistry(services: .preview())
    let scene = NotchSceneModel(layout: NotchLayout(metrics: .reference), theme: CrannyTheme())
    let viewModel = NotchViewModel(scene: scene, registry: registry)
    viewModel.pointerKeys = { (false, false) }
    return (DropRouter(scene: scene, viewModel: viewModel, registry: registry), viewModel, scene, registry)
}

/// C-SHELL-2: a Tray tile dragged out across its own open panel. The Tray offers no operation inside Cranny, so the
/// panel is no destination for it: no drag state, no `drag` hold, no enlarged drop zone once it has closed.
@Test func aDragFromCrannyItselfIsNoFileDrag() {
    let (router, viewModel, _, _) = makeRouter()
    let view = NSView(frame: CGRect(x: 0, y: 0, width: 400, height: 200))
    let pasteboard = filePasteboard()
    defer { pasteboard.releaseGlobally() }
    viewModel.send(.open(page: .tray, focus: nil, reason: .click))
    let ownTile = FakeDraggingInfo(pasteboard: pasteboard, source: NSView(), operations: [])
    #expect(router.dragUpdated(ownTile, in: view) == [])
    router.dragExited()
    router.dragEnded()
    #expect(viewModel.state.fileDrag == nil && viewModel.state.holds.isEmpty)
    #expect(!router.performDrop(ownTile, in: view))
    #expect(!DropRouter.accepts(source: nil, operations: []) && DropRouter.accepts(source: nil, operations: .copy))
}

/// A file drag from another app that the detector missed starts at the panel and ends with its session when it was
/// dropped elsewhere; one dropped here ends through the drop (the armed zone stays for the delivery).
@Test func aDragTheRouterStartedEndsWithItsSession() {
    let (router, viewModel, _, _) = makeRouter()
    let view = NSView(frame: CGRect(x: 0, y: 0, width: 400, height: 200))
    let pasteboard = filePasteboard()
    defer { pasteboard.releaseGlobally() }
    let external = FakeDraggingInfo(pasteboard: pasteboard, source: nil, operations: [.copy, .generic])
    #expect(router.dragUpdated(external, in: view) == .copy)
    #expect(viewModel.state.fileDrag != nil && viewModel.state.holds.contains(NotchMachineState.dragHold))
    router.dragExited()
    router.dragEnded()                                                          // dropped in Finder
    #expect(viewModel.state.fileDrag == nil && !viewModel.state.holds.contains(NotchMachineState.dragHold))
    router.dragEnded()                                                          // once only
    #expect(viewModel.state.fileDrag == nil)
}

/// A promise drop writes its files into `<caches>/tray/Incoming/<uuid>/`; once the taker has its copy, the folder goes.
@Test func promisedFilesAreDeletedAfterTheDrop() async throws {
    let (router, viewModel, scene, registry) = makeRouter()
    var received: [URL] = []
    scene.zones.setDropZone(NotchZones.DropZone(id: "test.keep", frame: CGRect(x: 0, y: 0, width: 100, height: 100), accepts: [.item]) {
        received = $0.fileURLs
        #expect($0.fileURLs.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })   // there while it is taken
        return true
    })
    viewModel.send(.open(page: nil, focus: nil, reason: .click))
    viewModel.send(.fileDragEntered([.jpeg]))
    scene.zones.dragUpdated(at: CGPoint(x: 50, y: 50), types: [.jpeg])
    let incoming = FilePromiseResolver.incomingRoot(paths: registry.services.paths)
    #expect(router.drop(urls: [], promises: [WritingPromise(name: "photo.jpg")]))
    for _ in 0..<200 where received.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
    #expect(received.map(\.lastPathComponent) == ["photo.jpg"])
    for _ in 0..<200 where !folders(in: incoming).isEmpty { try await Task.sleep(for: .milliseconds(10)) }
    #expect(folders(in: incoming).isEmpty)
    try? FileManager.default.removeItem(at: registry.services.paths.root.deletingLastPathComponent())
}

/// Leftovers of a crash mid-drop go at the next launch (and at quit).
@Test func theIncomingFolderIsSwept() async throws {
    let paths = AppPaths.temporary()
    defer { try? FileManager.default.removeItem(at: paths.root.deletingLastPathComponent()) }
    let stale = try #require(FilePromiseResolver.incomingDirectory(paths: paths))
    FileManager.default.createFile(atPath: stale.appending(path: "mail.pdf").path, contents: Data("x".utf8))
    await FilePromiseResolver.sweepIncoming(paths: paths)
    #expect(!FileManager.default.fileExists(atPath: FilePromiseResolver.incomingRoot(paths: paths).path))
    FilePromiseResolver.sweepIncomingNow(paths: paths)                          // nothing there: no error
}

private func folders(in url: URL) -> [String] {
    (try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []
}

/// Writes one file into the destination on AppKit's queue, then calls the reader (a source app exporting a photo).
nonisolated private final class WritingPromise: NSFilePromiseReceiver, @unchecked Sendable {
    private let name: String
    init(name: String) { self.name = name; super.init() }
    required init?(pasteboardPropertyList propertyList: Any, ofType type: NSPasteboard.PasteboardType) { nil }
    override var fileTypes: [String] { [UTType.jpeg.identifier] }
    override func receivePromisedFiles(atDestination destinationDir: URL, options: [AnyHashable: Any] = [:],
                                       operationQueue: OperationQueue, reader: @escaping (URL, (any Error)?) -> Void) {
        nonisolated(unsafe) let reader = reader
        let url = destinationDir.appending(path: name)
        operationQueue.addOperation {
            FileManager.default.createFile(atPath: url.path, contents: Data("x".utf8))
            reader(url, nil)
        }
    }
}
