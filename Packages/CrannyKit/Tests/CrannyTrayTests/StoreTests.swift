// TrayStore with temporary folders, PreviewNotchControl and a recording TraySystem: keeping, caps, persistence,
// retention, pipelines with Undo, actions, the TrayIntake port.
import CrannyCore
import Foundation
import Testing
import UniformTypeIdentifiers
@testable import CrannyTray

@MainActor @Suite struct StoreTests {
    let services = CrannyServices.preview()
    let base = Fixtures.folder("store")
    var directories: TrayDirectories { .temporary(base) }
    var notch: PreviewNotchControl { services.notch as? PreviewNotchControl ?? PreviewNotchControl() }

    func makeStore(system: RecordingTraySystem = RecordingTraySystem()) -> TrayStore {
        TrayStore(settings: services.settings, notch: services.notch, haptics: services.haptics, system: system, directories: directories)
    }

    func waitForJobs(_ store: TrayStore) async {
        for _ in 0..<400 where !store.jobs.filter({ $0.failure == nil }).isEmpty { try? await Task.sleep(for: .milliseconds(10)) }
    }

    // MARK: Keeping

    @Test func keepAddsNewestFirstAndOpensTheTray() async throws {
        let store = makeStore()
        let source = Fixtures.folder("src")
        #expect(await store.keep([Fixtures.text("a.txt", in: source)]))
        #expect(await store.keep([Fixtures.text("b.txt", in: source), Fixtures.text("c.txt", in: source)]))
        #expect(store.items.map(\.name) == ["b.txt", "c.txt", "a.txt"])
        #expect(store.items.allSatisfy { store.url($0.id) != nil })
        #expect(notch.calls.filter { $0 == "open(tray,-,drag)" }.count == 2)
        services.settings[TraySettings.opensTrayOnDrop] = false
        await store.keep([Fixtures.text("d.txt", in: source)])
        #expect(notch.calls.filter { $0.hasPrefix("open") }.count == 2)
        #expect(await store.keep([]) == false)
    }

    @Test func theSameFileIsNotKeptTwice() async {
        let store = makeStore()
        let source = Fixtures.folder("src")
        let a = Fixtures.text("a.txt", in: source), b = Fixtures.text("b.txt", in: source)
        await store.keep([a, b])
        await store.keep([b])
        #expect(store.items.map(\.name) == ["b.txt", "a.txt"])
        #expect(store.items.count == 2)
    }

    @Test func theOldestItemsLeaveAtTheCap() async {
        services.settings[TraySettings.maxItems] = 2
        let store = makeStore()
        let source = Fixtures.folder("src")
        var clock = Date()
        store.now = { clock }
        for name in ["1.txt", "2.txt", "3.txt"] {
            await store.keep([Fixtures.text(name, in: source)], opensTray: false)
            clock += 10
        }
        #expect(store.items.map(\.name) == ["3.txt", "2.txt"])
    }

    @Test func removeDeletesOwnedCopies() async throws {
        let store = makeStore()
        await store.keep([Fixtures.text("a.txt", in: Fixtures.folder("src"))], opensTray: false)
        let item = try #require(store.items.first)
        let copy = try #require(store.url(item.id))
        store.selection.set([item.id])
        store.remove([item.id])
        #expect(store.items.isEmpty && store.selection.isEmpty)
        for _ in 0..<100 where FileManager.default.fileExists(atPath: copy.path) { try? await Task.sleep(for: .milliseconds(10)) }
        #expect(!FileManager.default.fileExists(atPath: copy.path))
    }

    // MARK: Persistence and retention

    @Test func itemsSurviveARelaunch() async {
        let first = makeStore()
        await first.keep([Fixtures.text("a.txt", in: Fixtures.folder("src"))], opensTray: false)
        await first.saveNow()
        let second = makeStore()
        await second.load()
        #expect(second.items.map(\.name) == ["a.txt"])
        #expect(second.url(second.items[0].id) != nil)
    }

    @Test func clearOnQuitEmptiesTheTray() async throws {
        services.settings[TraySettings.retention] = .clearOnQuit
        let store = makeStore()
        await store.keep([Fixtures.text("a.txt", in: Fixtures.folder("src"))], opensTray: false)
        let copy = try #require(store.url(store.items[0].id))
        store.terminate()
        #expect(store.items.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: copy.path))
        let next = makeStore()
        await next.load()
        #expect(next.items.isEmpty)
    }

    @Test func clearOnQuitAlsoAppliesAfterACrash() async {
        let crashed = makeStore()
        await crashed.keep([Fixtures.text("a.txt", in: Fixtures.folder("src"))], opensTray: false)
        await crashed.saveNow()                                            // no terminate: the app died
        services.settings[TraySettings.retention] = .clearOnQuit
        let next = makeStore()
        await next.load()
        #expect(next.items.isEmpty)
    }

    @Test func oneDayRetentionAppliesOnLaunch() async {
        let first = makeStore()
        first.now = { Date().addingTimeInterval(-2 * Retention.oneDay) }
        await first.keep([Fixtures.text("old.txt", in: Fixtures.folder("src"))], opensTray: false)
        first.now = { Date() }
        await first.keep([Fixtures.text("new.txt", in: Fixtures.folder("src"))], opensTray: false)
        await first.saveNow()
        services.settings[TraySettings.retention] = .afterOneDay
        let next = makeStore()
        await next.load()
        #expect(next.items.map(\.name) == ["new.txt"])
    }

    // MARK: Pipelines

    @Test func pipelineResultsSlideInBesideTheSourceWithUndo() async throws {
        let system = RecordingTraySystem()
        let store = makeStore(system: system)
        await store.keep([Fixtures.image("hero.png", in: Fixtures.folder("src"), width: 640, height: 480),
                          Fixtures.text("notes.txt", in: Fixtures.folder("src"))], opensTray: false)
        let source = try #require(store.items.first { $0.name == "hero.png" })
        store.run(BuiltinPipelines.convert(.jpeg), on: [source.id])
        #expect(store.job(for: source.id) != nil)
        await waitForJobs(store)
        #expect(store.items.map(\.name) == ["hero.png", "hero.jpg", "notes.txt"])
        let result = store.items[1]
        let file = try #require(store.url(result.id))
        // The Tray owns the source copy, so the result goes to Downloads (here: the test's folder).
        #expect(file.deletingLastPathComponent().standardizedFileURL.path == directories.downloads.standardizedFileURL.path)
        #expect(!result.isOwned)
        #expect(store.freshItems.contains(result.id))
        #expect(store.selection.selected == [result.id])
        #expect(store.undoOffer?.itemIDs == [result.id])
        #expect(system.calls.contains("announce"))
        store.undo()
        #expect(store.items.map(\.name) == ["hero.png", "notes.txt"])
        for _ in 0..<100 where system.trashed.isEmpty { try? await Task.sleep(for: .milliseconds(10)) }
        #expect(system.trashed == [file])
    }

    @Test func failuresAreShownOnTheSourceTile() async throws {
        let store = makeStore()
        await store.keep([Fixtures.text("notes.txt", in: Fixtures.folder("src"))], opensTray: false)
        let item = try #require(store.items.first)
        store.run(BuiltinPipelines.compress, on: [item.id])
        await waitForJobs(store)
        #expect(store.failures[item.id] == TrayError.unsupportedFile("notes.txt").errorDescription)
        #expect(store.items.count == 1)
        store.click(item.id, modifiers: [])
        #expect(store.failures[item.id] == nil)
    }

    @Test func copyPathsConfirmsInTheBand() async throws {
        let system = RecordingTraySystem()
        let store = makeStore(system: system)
        await store.keep([Fixtures.text("a.txt", in: Fixtures.folder("src"))], opensTray: false)
        let item = try #require(store.items.first)
        store.copyPaths(item.id)
        #expect(system.copiedText == store.url(item.id)?.path)
        #expect(notch.calls.contains("flash(link)"))
        store.run(BuiltinPipelines.copyPaths, on: [item.id])
        await waitForJobs(store)
        #expect(notch.calls.filter { $0 == "flash(link)" }.count == 2)
        #expect(store.undoOffer == nil)                                     // nothing was written
    }

    @Test func droppedFilesRunAndTheResultIsKept() async throws {
        let store = makeStore()
        let source = Fixtures.folder("desktop")
        let photo = Fixtures.image("photo.png", in: source, width: 640, height: 480)
        #expect(await store.run(BuiltinPipelines.convert(.jpeg), dropped: [photo]))
        await waitForJobs(store)
        let result = try #require(store.items.first)
        #expect(result.name == "photo.jpg")
        // A user file: the result goes next to it.
        #expect(store.url(result.id)?.deletingLastPathComponent().standardizedFileURL.path == source.standardizedFileURL.path)
        #expect(notch.calls.contains("open(tray,-,drag)"))
    }

    @Test func aFailedDropRunStaysUntilDismissed() async throws {
        let store = makeStore()
        let note = Fixtures.text("notes.txt", in: Fixtures.folder("desktop"))
        #expect(await store.run(BuiltinPipelines.compress, dropped: [note]))
        await waitForJobs(store)
        let job = try #require(store.jobs.first)
        #expect(job.failure != nil && job.placeholderName == "notes.txt")
        store.dismissJob(job.id)
        #expect(store.jobs.isEmpty)
    }

    @Test func cancellingARunLeavesNoResult() async throws {
        let store = makeStore()
        let source = Fixtures.folder("src")
        await store.keep((0..<4).map { Fixtures.image("p\($0).png", in: source, width: 1600, height: 1200) }, opensTray: false)
        store.run(BuiltinPipelines.compress, on: store.order)
        let job = try #require(store.jobs.first)
        store.cancel(job.id)
        await waitForJobs(store)
        #expect(store.jobs.isEmpty)
        #expect(store.items.count == 4)
    }

    // MARK: Actions and the port

    @Test func sharingGoesThroughTheShell() async throws {
        let system = RecordingTraySystem()
        let store = makeStore(system: system)
        let source = Fixtures.folder("src")
        await store.keep([Fixtures.text("a.txt", in: source), Fixtures.text("b.txt", in: source)], opensTray: false)
        store.selectAll()
        store.airDrop()
        store.share()
        for _ in 0..<100 where !notch.calls.contains("airdrop(2)") { try? await Task.sleep(for: .milliseconds(5)) }
        #expect(notch.calls.contains("airdrop(2)") && notch.calls.contains("share(2)"))
        #expect(await store.airDrop(dropped: [Fixtures.text("c.txt", in: source)]))
        store.toggleQuickLook()
        #expect(system.calls.contains("quickLook(2,0)"))
        store.toggleQuickLook()
        #expect(system.calls.last == "closeQuickLook")
        store.copyFiles()
        store.reveal()
        store.open(store.order[1])                                         // not selected? it is (select all)
        #expect(system.calls.contains("copyFiles(2)") && system.calls.contains("reveal(2)") && system.calls.contains("open(2)"))
        store.clearSelection()
        store.open(store.order[1])
        #expect(system.calls.last == "open(1)")
    }

    @Test func dragOutHoldsCrannyOpenAndRemovesMovedFiles() async throws {
        let store = makeStore()
        await store.keep([Fixtures.text("a.txt", in: Fixtures.folder("src"))], opensTray: false)
        let item = try #require(store.items.first)
        store.dragOutBegan()
        #expect(notch.calls.last == "hold(true,tray.dragOut)")
        let copy = try #require(store.url(item.id))
        try FileManager.default.moveItem(at: copy, to: Fixtures.folder("finder").appending(path: "a.txt"))   // what Finder does
        store.dragOutEnded([item.id], movedOrDeleted: true)
        #expect(notch.calls.last == "hold(false,tray.dragOut)")
        for _ in 0..<100 where !store.items.isEmpty { try? await Task.sleep(for: .milliseconds(10)) }
        #expect(store.items.isEmpty)
    }

    @Test func intakeKeepsDropsNoZoneTook() async {
        let store = makeStore()
        let intake = TrayIntakeService(store: store)
        #expect(intake.itemCount == 0)
        let file = Fixtures.text("a.txt", in: Fixtures.folder("src"))
        #expect(await intake.accept(DropPayload(fileURLs: [file], contentTypes: [.plainText])))
        #expect(intake.itemCount == 1)
        _ = intake.catchView(for: [.png])
    }

    @Test func commandsOfferClearOnlyWithItems() async {
        let store = makeStore()
        let commands = TrayCommands(store: store)
        #expect(commands.commands(matching: "").map(\.id) == ["tray.open"])
        await store.keep([Fixtures.text("a.txt", in: Fixtures.folder("src"))], opensTray: false)
        #expect(commands.commands(matching: "").map(\.id) == ["tray.open", "tray.clear"])
        commands.commands(matching: "").last?.perform()
        #expect(store.items.isEmpty)
        #expect(commands.commands(matching: "zzz").isEmpty)
    }
}
