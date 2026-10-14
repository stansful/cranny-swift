// What the Tray's routine events invalidate: a progress tick changes only its job's box, a refresh that finds nothing
// new and a click on a tile without an error publish nothing, nearby expiries leave together, the catch view's
// pipeline lookup matches the full list, and removed items leave the thumbnail LRU.
import CrannyCore
import Foundation
import Observation
import os
import Testing
@testable import CrannyTray

@MainActor @Suite struct InvalidationTests {
    let services = CrannyServices.preview()
    let base = Fixtures.folder("invalidation")

    func makeStore() -> TrayStore {
        TrayStore(settings: services.settings, notch: services.notch, haptics: services.haptics, system: RecordingTraySystem(),
                  directories: .temporary(base))
    }

    // MARK: Progress

    @Test func aTickMovesItsBoxForwardAndOnlyWhenItChanges() {
        let box = TrayJobProgress(0.2)
        let changed = OSAllocatedUnfairLock(initialState: false)
        withObservationTracking { _ = box.fraction } onChange: { changed.withLock { $0 = true } }
        box.advance(to: 0.1)                                    // never goes back
        box.advance(to: 0.2)                                    // the same value notifies nobody
        #expect(!changed.withLock { $0 })
        #expect(box.fraction == 0.2)
        box.advance(to: 0.6)
        #expect(changed.withLock { $0 })
        #expect(box.fraction == 0.6)
    }

    @Test func aRunReportsThroughItsBoxAndDropsItWhenDone() async throws {
        let store = makeStore()
        let source = Fixtures.folder("src")
        await store.keep([Fixtures.image("a.png", in: source), Fixtures.image("b.png", in: source)], opensTray: false)
        store.run(BuiltinPipelines.convert(.jpeg), on: store.order)
        let job = try #require(store.jobs.first)
        #expect(store.liveProgress[job.id] != nil)
        #expect(store.progress(of: job) < 1)
        for _ in 0..<400 where !store.jobs.isEmpty { try? await Task.sleep(for: .milliseconds(10)) }
        #expect(store.jobs.isEmpty)
        #expect(store.liveProgress.isEmpty)
        // A job without a box (previews, QA, the snapshot states) shows the value it was made with.
        #expect(store.progress(of: TrayJob(id: UUID(), pipelineID: "x", title: "X", sourceIDs: [], placeholderName: nil,
                                           progress: 0.4)) == 0.4)
    }

    // MARK: Refresh and clicks

    @Test func aRefreshThatFindsNothingNewInvalidatesNoTile() async throws {
        let store = makeStore()
        await store.keep([Fixtures.text("a.txt", in: Fixtures.folder("src"))], opensTray: false)
        await store.refreshLocations()                          // settles the URL as the bookmark resolves it
        let id = try #require(store.order.first)
        let changed = OSAllocatedUnfairLock(initialState: false)
        withObservationTracking {
            _ = store.url(id)
            _ = store.items
        } onChange: { changed.withLock { $0 = true } }
        await store.refreshLocations()
        #expect(!changed.withLock { $0 })
        #expect(store.url(id) != nil)
    }

    @Test func aClickOnATileWithoutAnErrorLeavesTheErrorsAlone() async throws {
        let store = makeStore()
        await store.keep([Fixtures.text("a.txt", in: Fixtures.folder("src"))], opensTray: false)
        let id = try #require(store.order.first)
        let changed = OSAllocatedUnfairLock(initialState: false)
        withObservationTracking { _ = store.failures } onChange: { changed.withLock { $0 = true } }
        store.click(id, modifiers: [])
        #expect(!changed.withLock { $0 })
        // A click still clears a tile's error.
        store.failures[id] = "Nope"
        store.click(id, modifiers: [])
        #expect(store.failures[id] == nil)
    }

    // MARK: Retention

    @Test func expiriesWithinAMinuteLeaveTogether() async {
        let store = makeStore()
        let source = Fixtures.folder("src")
        let start = Date()
        store.now = { start.addingTimeInterval(-(Retention.oneDay - 30)) }        // due in 30 s
        await store.keep([Fixtures.text("soon.txt", in: source)], opensTray: false)
        store.now = { start.addingTimeInterval(-(Retention.oneDay - 600)) }       // due in 10 min
        await store.keep([Fixtures.text("later.txt", in: source)], opensTray: false)
        store.now = { start }
        services.settings[TraySettings.retention] = .afterOneDay                // applies the policy now
        for _ in 0..<200 where store.items.count == 2 { try? await Task.sleep(for: .milliseconds(10)) }
        #expect(store.items.map(\.name) == ["later.txt"])
    }

    // MARK: Lookups and caches

    @Test func theCatchViewsLookupMatchesTheFullList() {
        let user = PipelineDefinition(id: "user.a", name: "Mine", symbol: "wand.and.stars", steps: [.zip])
        let shadow = PipelineDefinition(id: BuiltinPipelines.zip.id, name: "Not the built-in", symbol: "x", steps: [.unzip])
        let all = BuiltinPipelines.all(userPipelines: [user, shadow])
        for id in all.map(\.id) + ["user.missing", ""] {
            #expect(BuiltinPipelines.definition(id, userPipelines: [user, shadow]) == all.first { $0.id == id })
        }
    }

    @Test func forgettingKeysLeavesTheRestInOrder() {
        var cache = LRUCache<String, Int>(capacity: 3)
        cache.insert(1, for: "a#88")
        cache.insert(2, for: "b#88")
        cache.insert(3, for: "a#44")
        cache.removeValues { $0.hasPrefix("a#") }
        #expect(cache.count == 1)
        cache.insert(4, for: "c#88")
        cache.insert(5, for: "d#88")
        #expect(cache.value(for: "b#88") == 2)                                  // a freed slot is never counted twice
        cache.insert(6, for: "e#88")
        #expect(cache.value(for: "c#88") == nil)
        #expect(cache.count == 3)
    }
}
