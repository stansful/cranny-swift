// Drops with file promises (ARCHITECTURE.md §5.6): AppKit calls the promise readers on a background operation
// queue, so the reader must not be main-actor isolated (Swift 6 would trap on its executor check); a source that
// never delivers is given up; and a promise that resolves slowly still reaches the zone that was armed when the
// files were dropped, because the panel is held until the payload is handed over. No windows: a fake promise
// receiver delivers files it writes into the destination, on the queue AppKit would use.
import AppKit
@testable import CrannyCore
import CrannyNotchUI
import Foundation
import Testing
import UniformTypeIdentifiers
import os
@testable import CrannyAppShell

/// Delivers `files` (writes them, then calls the reader) on the given operation queue after `delay`, like a source
/// app exporting a photo; or never, like a source that crashed.
nonisolated private final class FakePromise: NSFilePromiseReceiver, @unchecked Sendable {
    private let files: [String]
    private let delay: TimeInterval
    private let delivers: Bool

    init(files: [String], delay: TimeInterval = 0, delivers: Bool = true) {
        self.files = files; self.delay = delay; self.delivers = delivers
        super.init()
    }

    required init?(pasteboardPropertyList propertyList: Any, ofType type: NSPasteboard.PasteboardType) { nil }

    override var fileTypes: [String] { files.map { _ in UTType.jpeg.identifier } }

    override func receivePromisedFiles(atDestination destinationDir: URL, options: [AnyHashable: Any] = [:],
                                       operationQueue: OperationQueue, reader: @escaping (URL, (any Error)?) -> Void) {
        guard delivers else { return }
        nonisolated(unsafe) let reader = reader
        let files = files, delay = delay
        operationQueue.addOperation {
            #expect(!Thread.isMainThread)                                      // where AppKit calls readers
            Thread.sleep(forTimeInterval: delay)
            for name in files {
                let url = destinationDir.appending(path: name)
                FileManager.default.createFile(atPath: url.path, contents: Data("x".utf8))
                reader(url, nil)
            }
        }
    }
}

private func temporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appending(path: "cranny-drop-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func waitUntil(_ seconds: Double, _ condition: () -> Bool) async throws {
    let deadline = ProcessInfo.processInfo.systemUptime + seconds
    while !condition(), ProcessInfo.processInfo.systemUptime < deadline { try await Task.sleep(for: .milliseconds(10)) }
}

/// The reader runs on AppKit's background queue: it must survive that (the review's crash) and collect every file.
@Test func promisedFilesArriveFromABackgroundQueue() async throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let urls = await FilePromiseResolver.resolve([FakePromise(files: ["a.jpg", "b.jpg"]), FakePromise(files: ["c.jpg"])],
                                                 into: directory)
    #expect(Set(urls.map(\.lastPathComponent)) == ["a.jpg", "b.jpg", "c.jpg"])
}

@Test func aPromiseThatNeverArrivesIsGivenUp() async throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let start = ProcessInfo.processInfo.systemUptime
    let urls = await FilePromiseResolver.resolve([FakePromise(files: ["lost.jpg"], delivers: false)], into: directory,
                                                 timeout: .milliseconds(150))
    #expect(urls.isEmpty && ProcessInfo.processInfo.systemUptime - start < 5)
}

/// Finishing cancels the timeout: no minute-long sleep per promise outlives the drop.
@Test func aFinishedPromiseCancelsItsTimeout() async throws {
    let collector = PromiseCollector(expected: 1)
    let finished = OSAllocatedUnfairLock<[URL]?>(initialState: nil)
    collector.onFinish = { urls in finished.withLock { $0 = urls } }
    collector.armTimeout(.seconds(60))
    #expect(collector.hasPendingTimeout)
    let reader = FilePromiseResolver.makeReader(for: collector)
    let url = URL(fileURLWithPath: "/tmp/x.jpg")
    await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
        DispatchQueue.global().async { reader(url, nil); done.resume() }
    }
    #expect(finished.withLock { $0 } == [url] && !collector.hasPendingTimeout)
    collector.giveUp()                                                          // already done: no second finish
    #expect(finished.withLock { $0 } == [url])
}

/// A photo dropped on an action zone (Compress, AirDrop…) is exported by the source first. Meanwhile the grid
/// would close (the pointer is outside) and the zone's view with it; the `drop` hold keeps both until the payload
/// is handed to that zone, then the panel closes as usual.
@Test func aSlowPromiseReachesTheZoneArmedAtTheDrop() async throws {
    let registry = ModuleRegistry(services: .preview())
    let scene = NotchSceneModel(layout: NotchLayout(metrics: .reference), theme: CrannyTheme())
    let viewModel = NotchViewModel(scene: scene, registry: registry)
    let router = DropRouter(scene: scene, viewModel: viewModel, registry: registry)
    var received: [URL] = []
    let zone: DropZoneID = "test.compress"
    scene.zones.setDropZone(NotchZones.DropZone(id: zone, frame: CGRect(x: 0, y: 0, width: 100, height: 100), accepts: [.item]) {
        received = $0.fileURLs
        return true
    })
    // As in the app: the zone's view leaves when the panel closes (`onDisappear` → `removeDropZone`).
    viewModel.didSync = { if viewModel.state.isClosed { scene.zones.removeDropZone(zone) } }
    viewModel.send(.open(page: nil, focus: nil, reason: .programmatic))         // the grid; the pointer is outside
    viewModel.send(.fileDragEntered([.jpeg]))
    scene.zones.dragUpdated(at: CGPoint(x: 50, y: 50), types: [.jpeg])
    #expect(scene.zones.armedDropZone == zone)

    #expect(router.drop(urls: [], promises: [FakePromise(files: ["photo.jpg"], delay: 0.6)]))
    #expect(viewModel.state.holds.contains(NotchMachineState.dropHold))
    try await waitUntil(10) { !received.isEmpty }
    #expect(received.map(\.lastPathComponent) == ["photo.jpg"])
    try await waitUntil(10) { viewModel.state.isClosed }
    #expect(viewModel.state.isClosed && viewModel.state.holds.isEmpty)          // then the grace closes it
}

/// Plain file URLs need no hold: the zone is chosen before the panel could close.
@Test func droppedFileURLsReachTheArmedZoneWithoutAHold() async throws {
    let registry = ModuleRegistry(services: .preview())
    let scene = NotchSceneModel(layout: NotchLayout(metrics: .reference), theme: CrannyTheme())
    let viewModel = NotchViewModel(scene: scene, registry: registry)
    let router = DropRouter(scene: scene, viewModel: viewModel, registry: registry)
    var received: [URL] = []
    scene.zones.setDropZone(NotchZones.DropZone(id: "test.zip", frame: CGRect(x: 0, y: 0, width: 100, height: 100), accepts: [.item]) {
        received = $0.fileURLs
        return true
    })
    viewModel.send(.open(page: nil, focus: nil, reason: .programmatic))
    scene.zones.dragUpdated(at: CGPoint(x: 50, y: 50), types: [.pdf])
    let file = URL(fileURLWithPath: "/tmp/report.pdf")
    #expect(router.drop(urls: [file], promises: []))
    #expect(!viewModel.state.holds.contains(NotchMachineState.dropHold))
    try await waitUntil(10) { !received.isEmpty }
    #expect(received == [file])
    #expect(!router.drop(urls: [], promises: []))                                 // nothing dropped: refused
}
