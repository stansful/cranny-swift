// TrayStore edge cases found in review: a damaged or missing index, repeat drops of edited files, the cap after a
// repeat drop or a lower setting, a refresh racing an insert, AirDrop of temporary files, files that cannot be kept,
// and Stop on every path. Temporary folders and recording doubles only.
import AppKit
import CrannyCore
import Foundation
import Testing
import UniformTypeIdentifiers
@testable import CrannyTray

@MainActor @Suite struct StoreRobustnessTests {
    let services = CrannyServices.preview()
    let base = Fixtures.folder("robust")
    var directories: TrayDirectories { .temporary(base) }
    var notch: PreviewNotchControl { services.notch as? PreviewNotchControl ?? PreviewNotchControl() }

    func makeStore(system: RecordingTraySystem = RecordingTraySystem(), notch: (any NotchControl)? = nil) -> TrayStore {
        TrayStore(settings: services.settings, notch: notch ?? services.notch, haptics: services.haptics, system: system,
                  directories: directories)
    }

    func waitUntil(_ condition: @MainActor () -> Bool) async {
        for _ in 0..<300 where !condition() { try? await Task.sleep(for: .milliseconds(10)) }
    }

    // MARK: Index

    @Test func aDamagedIndexKeepsEveryCopy() async throws {
        let first = makeStore()
        await first.keep([Fixtures.text("only-copy.txt", in: Fixtures.folder("src"))], opensTray: false)
        let copy = try #require(first.url(first.items[0].id))
        try Data("{\"items\":[{\"id\":".utf8).write(to: directories.root.appending(path: "index.json"))   // truncated write
        let next = makeStore()
        await next.load()
        #expect(next.items.map(\.name) == ["only-copy.txt"])
        #expect(FileManager.default.fileExists(atPath: copy.path))
        #expect(next.url(next.items[0].id) == copy)
        await next.saveNow()                                                // the rebuilt index is written
        let third = makeStore()
        await third.load()
        #expect(third.items.map(\.id) == next.items.map(\.id))
    }

    @Test func aKeptCopyIsInTheIndexAtOnce() async throws {
        let first = makeStore()
        await first.keep([Fixtures.text("a.txt", in: Fixtures.folder("src"))], opensTray: false)
        // No saveNow and no terminate: the app dies right after the drop.
        let next = makeStore()
        await next.load()
        #expect(next.items.map(\.name) == ["a.txt"])
    }

    @Test func aMissingIndexRecoversTheCopies() async throws {
        let first = makeStore()
        await first.keep([Fixtures.text("a.txt", in: Fixtures.folder("src"))], opensTray: false)
        try FileManager.default.removeItem(at: directories.root.appending(path: "index.json"))
        let next = makeStore()
        await next.load()
        #expect(next.items.map(\.name) == ["a.txt"])
    }

    // MARK: Repeat drops

    @Test func reDroppingAnEditedFileKeepsTheNewVersion() async throws {
        let store = makeStore()
        let file = Fixtures.text("Report.txt", in: Fixtures.folder("src"), contents: "version 1")
        await store.keep([file], opensTray: false)
        let oldCopy = try #require(store.url(store.items[0].id))
        try "version 2 (edited)".write(to: file, atomically: true, encoding: .utf8)
        await store.keep([file], opensTray: false)
        #expect(store.items.count == 1)
        let kept = try #require(store.url(store.items[0].id))
        #expect(try String(contentsOf: kept, encoding: .utf8) == "version 2 (edited)")
        await waitUntil { !FileManager.default.fileExists(atPath: oldCopy.path) }
        #expect(!FileManager.default.fileExists(atPath: oldCopy.path))     // the outdated copy is gone
    }

    @Test func reDroppingAnUnchangedFileMovesItToTheFrontAsNew() async throws {
        let store = makeStore()
        var clock = Date()
        store.now = { clock }
        let source = Fixtures.folder("src")
        let a = Fixtures.text("A.txt", in: source), b = Fixtures.text("B.txt", in: source)
        await store.keep([a], opensTray: false)
        let id = store.items[0].id
        clock += 10
        await store.keep([b], opensTray: false)
        clock += 10
        await store.keep([a], opensTray: false)
        #expect(store.items.map(\.name) == ["A.txt", "B.txt"])
        #expect(store.items[0].id == id)                                    // the same copy, not a second one
        #expect(store.items[0].addedAt == clock)
    }

    // MARK: The cap

    @Test func theCapKeepsTheItemTheUserJustDroppedAgain() async {
        services.settings[TraySettings.maxItems] = 2
        let store = makeStore()
        var clock = Date()
        store.now = { clock }
        let source = Fixtures.folder("src")
        let a = Fixtures.text("A.txt", in: source), b = Fixtures.text("B.txt", in: source), c = Fixtures.text("C.txt", in: source)
        await store.keep([a], opensTray: false); clock += 10
        await store.keep([b], opensTray: false); clock += 10
        await store.keep([a], opensTray: false); clock += 10
        await store.keep([c], opensTray: false)
        #expect(store.items.map(\.name) == ["C.txt", "A.txt"])
    }

    @Test func aLowerCapAppliesAtOnce() async {
        let store = makeStore()
        var clock = Date()
        store.now = { clock }
        let source = Fixtures.folder("src")
        for name in ["1.txt", "2.txt", "3.txt", "4.txt"] {
            await store.keep([Fixtures.text(name, in: source)], opensTray: false)
            clock += 10
        }
        services.settings[TraySettings.maxItems] = 2
        await waitUntil { store.items.count == 2 }
        #expect(store.items.map(\.name) == ["4.txt", "3.txt"])
    }

    @Test func oneDropLargerThanTheCapIsKeptWhole() async {
        services.settings[TraySettings.maxItems] = 2
        let store = makeStore()
        let source = Fixtures.folder("src")
        await store.keep((0..<3).map { Fixtures.text("\($0).txt", in: source) }, opensTray: false)
        #expect(store.items.count == 3)                                     // a file the user just dropped never vanishes
        await store.keep([Fixtures.text("next.txt", in: source)], opensTray: false)
        #expect(store.items.count == 2)                                     // back at the cap on the next change
    }

    // MARK: Refresh vs. insert

    @Test func aRefreshKeepsTheURLOfAnItemAddedMeanwhile() async throws {
        let store = makeStore()
        let source = Fixtures.folder("src")
        await store.keep((0..<30).map { Fixtures.text("f\($0).txt", in: source) }, opensTray: false)
        let doomed = store.items[5].id
        let result = Fixtures.text("result.txt", in: source)
        let made = await store.storage.linkResults([result], now: Date())
        let refresh = Task { await store.refreshLocations() }               // the Tray page appears
        for _ in 0..<3 { await Task.yield() }                               // it took its snapshot and is resolving
        store.insert(made.map(\.item), urls: [made[0].item.id: result], after: nil)   // a pipeline result lands
        store.remove([doomed])                                              // and the user removes an item
        await refresh.value
        #expect(store.url(made[0].item.id) == result)
        #expect(store.url(doomed) == nil)
    }

    // MARK: AirDrop of dropped files

    @Test func temporaryFilesDroppedOnAirDropOutliveTheDrop() async throws {
        let sharing = SharingNotch()
        let store = makeStore(notch: sharing)
        let incoming = directories.temporaryRoots[0].appending(path: "promise", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: incoming, withIntermediateDirectories: true)
        let promised = Fixtures.text("IMG_0001.heic", in: incoming)
        let user = Fixtures.text("Brief.pdf", in: Fixtures.folder("desktop"))
        sharing.holdsSheet = true
        #expect(await store.airDrop(dropped: [promised, user]))
        try FileManager.default.removeItem(at: incoming)                   // the shell cleans up after the drop
        await waitUntil { sharing.received.count == 1 }
        let sent = try #require(sharing.received.first)
        #expect(sent.count == 2 && sent[1] == user)                         // the user's own file is sent as it is
        #expect(sent[0].lastPathComponent == "IMG_0001.heic" && sent[0] != promised)
        #expect(sharing.existedWhenPresented == [true, true])
        #expect(FileManager.default.fileExists(atPath: sent[0].path))       // still there while the sheet is up
        sharing.finishSheet()
        await waitUntil { !FileManager.default.fileExists(atPath: sent[0].path) }
        #expect(!FileManager.default.fileExists(atPath: sent[0].path))      // staged copy removed afterwards
        #expect(FileManager.default.fileExists(atPath: user.path))
    }

    // MARK: Files that cannot be kept

    @Test func aFileThatCannotBeKeptShowsAnErrorTile() async throws {
        let system = RecordingTraySystem()
        let store = makeStore(system: system)
        let missing = Fixtures.folder("src").appending(path: "Gone.pdf")
        #expect(await store.keep([missing], opensTray: false))              // handled: the shell must not retry it
        let job = try #require(store.jobs.first)
        #expect(job.placeholderName == "Gone.pdf" && job.failure == TrayError.cannotRead("Gone.pdf").errorDescription)
        #expect(store.items.isEmpty)
        #expect(system.calls.contains("announce"))
        #expect(notch.calls.contains("open(tray,-,drag)"))                  // the Tray page was not showing
        await store.keep([missing], opensTray: false)
        #expect(store.jobs.count == 1)                                      // one tile per file, not one per attempt
        store.dismissFailedJobs()
        #expect(store.jobs.isEmpty)
    }

    @Test func errorsOnAVisibleTrayPageDoNotNavigate() async {
        let store = makeStore()
        store.pageDidAppear()
        await store.keep([Fixtures.folder("src").appending(path: "Gone.pdf")], opensTray: false)
        #expect(!notch.calls.contains { $0.hasPrefix("open") })
        store.pageDidDisappear()
        #expect(!store.isPageVisible)
    }

    // MARK: Stop

    @Test func stopCancelsTheSelectionsRunsElseEveryRun() async throws {
        let store = makeStore()
        let source = Fixtures.folder("src")
        await store.keep((0..<3).map { Fixtures.text("p\($0).txt", in: source) }, opensTray: false)
        let ids = store.order
        let first = UUID(), second = UUID(), dropped = UUID()
        store.jobs = [TrayJob(id: first, pipelineID: "builtin.compress", title: "Compress", sourceIDs: [ids[0]], placeholderName: nil),
                      TrayJob(id: second, pipelineID: "builtin.compress", title: "Compress", sourceIDs: [ids[1]], placeholderName: nil),
                      TrayJob(id: dropped, pipelineID: "builtin.zip", title: "Zip", sourceIDs: [], placeholderName: "a.txt")]
        store.selection.set([ids[1]])
        #expect(store.stoppableJobs().map(\.id) == [second])
        #expect(store.stopChipJobs.map(\.id) == [second])
        store.selection.set([ids[2]])                                       // nothing selected is running
        #expect(store.stoppableJobs().map(\.id) == [first, second, dropped])   // ⌘. stops everything
        #expect(store.stopChipJobs.isEmpty)                                 // but no chip reads as stopping the selection
        store.selection.clear()
        #expect(store.stopChipJobs.map(\.id) == [first, second, dropped])
        #expect(store.stoppableJobs(ids[0]).map(\.id) == [first])           // a tile's own menu or VoiceOver action
        store.jobs[0].failure = "failed"
        #expect(!store.stoppableJobs().contains { $0.id == first })         // failed runs are dismissed, not stopped
    }

    @Test func aRunningTileOffersStopInItsMenu() async throws {
        let store = makeStore()
        await store.keep([Fixtures.text("p.txt", in: Fixtures.folder("src"))], opensTray: false)
        let id = try #require(store.order.first)
        #expect(TrayContextMenu.make(for: id, store: store).items.first?.title == TrayItemCommand.open.title)
        store.jobs = [TrayJob(id: UUID(), pipelineID: "builtin.compress", title: "Compress", sourceIDs: [id], placeholderName: nil)]
        let menu = TrayContextMenu.make(for: id, store: store)
        #expect(menu.items.first?.title == TrayItemCommand.stopTitle)
        #expect(menu.items.dropFirst().first?.isSeparatorItem == true)
    }
}

/// A `NotchControl` whose AirDrop sheet stays up until the test finishes it, recording what it was given and whether
/// those files existed when it was shown. Nothing is shared.
@MainActor final class SharingNotch: NotchControl {
    private(set) var received: [[URL]] = []
    private(set) var existedWhenPresented: [Bool] = []
    var holdsSheet = false
    private var sheet: CheckedContinuation<Void, Never>?

    func finishSheet() { sheet?.resume(); sheet = nil }

    func presentAirDrop(_ urls: [URL]) async -> Bool {
        received.append(urls)
        existedWhenPresented = urls.map { FileManager.default.fileExists(atPath: $0.path) }
        if holdsSheet { await withCheckedContinuation { sheet = $0 } }
        return true
    }
    func open(page: PageID?, focus: WidgetID?, reason: OpenReason) {}
    func close() {}
    func togglePinned() {}
    func setHoldOpen(_ hold: Bool, reason: String) {}
    func setFocusMode(_ widget: WidgetID?) {}
    func requestPeek(_ activity: ActivityID) {}
    func requestKeyboardFocus() {}
    func setCalibrationOverlay(_ visible: Bool) {}
    func shapeFrameOnScreen() -> CGRect? { nil }
    func presentSharePicker(_ urls: [URL]) {}
    func flash(symbol: String, label: String) {}
    func addEventObserver(_ handler: @escaping @MainActor (NotchEvent) -> Void) -> UUID { UUID() }
    func removeEventObserver(_ id: UUID) {}
}
