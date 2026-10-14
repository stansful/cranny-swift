// The Shortcuts list on demand: one shared read, a stuck `shortcuts list` that ends as a failure instead of
// loading forever, a retry after a failure, and a read that stops with the module.
import CrannyCore
import Foundation
import Testing
@testable import CrannyQuickApps

@Test func aStuckReadFailsAndTheNextCallerReadsAgain() async {
    let gate = Gate()
    defer { gate.open() }
    let attempts = Counter()
    let listing = Data(shortcutListFixture.utf8)
    let fake = FakeCLI { _ in
        if attempts.next() == 1 { await gate.wait(); return CLIOutput() }     // hangs, deaf to its signals
        return CLIOutput(stdout: listing)
    }
    let catalog = ShortcutsCatalog(cli: fake.cli(listTimeout: .milliseconds(100)))
    await catalog.refresh()
    #expect(!gate.isOpen)                                                      // answered while the CLI was stuck
    #expect(catalog.state == .failed(.listFailed))
    #expect(catalog.shortcuts.isEmpty && !catalog.hasLoaded)
    #expect(gate.sawCancellation)                                              // the CLI was told to stop

    await catalog.refresh(maximumAge: 300)                                     // ⌘K, the add menu: not stuck behind it
    #expect(catalog.state == .loaded)
    #expect(catalog.shortcuts.count == 9)
    #expect(fake.calls.count == 2)
}

@Test func concurrentCallersShareOneBoundedRead() async {
    let gate = Gate()
    defer { gate.open() }
    let fake = FakeCLI { _ in await gate.wait(); return CLIOutput() }
    let catalog = ShortcutsCatalog(cli: fake.cli(listTimeout: .milliseconds(150)))
    async let settings: Void = catalog.refresh(maximumAge: 30)
    async let palette: Void = catalog.refresh(maximumAge: 300)
    _ = await (settings, palette)
    #expect(!gate.isOpen)
    #expect(fake.calls.count == 1)
    #expect(catalog.state == .failed(.listFailed))
}

@Test func aFailedReadIsRetriedEvenWhileTheListIsFresh() async {
    let attempts = Counter()
    let listing = Data(shortcutListFixture.utf8)
    let fake = FakeCLI { _ in
        attempts.next() == 2 ? CLIOutput(status: 1, stderr: Data("Error".utf8)) : CLIOutput(stdout: listing)
    }
    let catalog = ShortcutsCatalog(cli: fake.cli)
    await catalog.refresh()
    #expect(catalog.state == .loaded)
    await catalog.refresh()
    #expect(catalog.state == .failed(.listFailed))
    #expect(catalog.shortcuts.count == 9 && catalog.hasLoaded)                // the last list is kept
    await catalog.refresh(maximumAge: 300)                                     // failed: read again
    #expect(catalog.state == .loaded)
    #expect(fake.calls.count == 3)
    await catalog.refresh(maximumAge: 300)                                     // fresh and fine: not read again
    #expect(fake.calls.count == 3)
}

@Test func cancellingStopsAReadAndKeepsTheState() async {
    let gate = Gate()
    defer { gate.open() }
    let fake = FakeCLI { _ in await gate.wait(); return CLIOutput() }
    let catalog = ShortcutsCatalog(cli: fake.cli(listTimeout: .seconds(30)))
    let reader = Task { await catalog.refresh() }
    #expect(await waitUntil { catalog.state == .loading })
    catalog.cancel()
    await reader.value
    #expect(!gate.isOpen)
    #expect(catalog.state == .idle)
    #expect(gate.sawCancellation)
}

@Test func stoppingTheModuleStopsAShortcutListRead() async {
    let gate = Gate()
    defer { gate.open() }
    let fake = FakeCLI { _ in await gate.wait(); return CLIOutput() }
    let h = ModelHarness(cli: fake)
    await h.model.start()
    h.notch.emit(.paletteOpened)
    #expect(await waitUntil { h.model.shortcutsCatalog.state == .loading })
    h.model.stop()
    #expect(await waitUntil { h.model.shortcutsCatalog.state == .idle })
    #expect(gate.sawCancellation)
}
