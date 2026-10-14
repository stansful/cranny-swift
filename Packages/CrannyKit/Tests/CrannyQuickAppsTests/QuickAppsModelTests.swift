// The module's model with fakes: tiles, launching, running shortcuts, editing, notch events, name sync.
import CrannyCore
import Foundation
import Testing
import UniformTypeIdentifiers
@testable import CrannyQuickApps

private let morning = ShortcutEntry(id: "0D7A5B52-6A0E-4C38-9C1F-3E2F1B6D9A01", name: "Morning routine")
private let resize = ShortcutEntry(id: "5C1B1E0B-2B7A-4E59-8D3B-7A0C1F3E2D02", name: "Resize images")

@Test func tilesHideAppsThatAreNotInstalled() async {
    let h = ModelHarness(installed: ["a", "b"], apps: ["a", "gone", "b"], shortcuts: [morning])
    #expect(!h.model.isReady)
    await h.model.start()
    #expect(h.model.isReady)
    #expect(h.model.tiles.map(\.id) == [.app("a"), .app("b"), .shortcut(morning.id)])
    #expect(h.model.arrangement.contains(.app("gone")))
    h.model.stop()
}

@Test func defaultLauncherIsFinderSafariMailMusic() async {
    let h = ModelHarness()
    await h.model.start()
    #expect(h.model.tiles.map(\.id) == [.app("com.apple.finder"), .app("com.apple.Safari"), .app("com.apple.mail"), .app("com.apple.Music")])
    h.model.stop()
}

@Test func openingAnAppClosesThePanel() async {
    let h = ModelHarness(installed: ["a"], apps: ["a"])
    await h.model.start()
    let tile = h.model.tiles[0]
    h.model.activate(tile)
    #expect(h.notch.calls == ["close"])
    #expect(await waitUntil { h.launcher.opened == [FakeResolver.app("a").url] })
    #expect(!h.notch.calls.contains { $0.hasPrefix("flash") })
    h.model.stop()
}

@Test func openingAnAppKeepsAPinnedPanelOpen() async {
    // ARCHITECTURE.md §4.5: Pin holds the Nook open; the shell's close input would ignore it.
    let h = ModelHarness(installed: ["a"], apps: ["a"])
    await h.model.start()
    h.notch.emit(.opened(.click))
    h.notch.emit(.pinned(true))
    h.model.activate(h.model.tiles[0])
    #expect(await waitUntil { h.launcher.opened.count == 1 })
    #expect(!h.notch.calls.contains("close"))
    h.notch.emit(.pinned(false))
    h.model.activate(h.model.tiles[0])
    #expect(h.notch.calls == ["close"])
    h.model.stop()
}

@Test func openingAnAppKeepsTheDemoModePanelOpen() async {
    // ARCHITECTURE.md §4.4: Demo mode never auto-closes.
    let h = ModelHarness(installed: ["a"], apps: ["a"])
    await h.model.start()
    h.environment.isDemoMode = true
    h.model.activate(h.model.tiles[0])
    #expect(await waitUntil { h.launcher.opened.count == 1 })
    #expect(h.notch.calls.isEmpty)
    h.model.stop()
}

@Test func anAppThatFailsToOpenSaysSoInTheNotch() async {
    let h = ModelHarness(installed: ["a"], apps: ["a"])
    await h.model.start()
    h.launcher.failing = true
    h.model.activate(h.model.tiles[0])
    #expect(h.notch.calls.first == "close")                                // closes at once, like a menu
    #expect(await waitUntil { h.notch.calls.contains("flash(exclamationmark)") })
    #expect(h.launcher.opened.isEmpty)
    h.model.stop()
}

@Test func shortcutRunFlashesItsResultOnlyWhileItsTileIsNotOnScreen() async {
    let h = ModelHarness(apps: [], shortcuts: [morning, resize], cli: FakeCLI(listing: shortcutListFixture, failing: [resize.id]))
    await h.model.start()
    h.model.toggleRun(morning)                                             // panel closed: flash "Done"
    #expect(await waitUntil { h.notch.calls.contains("flash(checkmark.circle.fill)") })
    h.notch.emit(.opened(.click))
    h.model.present([.shortcut(morning.id), .shortcut(resize.id)], by: UUID())
    h.model.toggleRun(resize)                                              // its tile is on screen: badge only
    #expect(await waitUntil { h.model.runs.state(of: resize.id) == .failed(.shortcutFailed) })
    #expect(!h.notch.calls.contains("flash(exclamationmark)"))
    h.model.stop()
}

@Test func aShortcutInOverflowFlashesItsResultWhileOpen() async {
    // Regression: the first shortcut added to the default launcher lands in "+2"; its result was invisible.
    let h = ModelHarness(apps: [], shortcuts: [morning, resize], cli: FakeCLI(listing: shortcutListFixture, failing: [resize.id]))
    await h.model.start()
    h.notch.emit(.opened(.click))
    let launcher = UUID()
    h.model.present([.shortcut(morning.id)], by: launcher)                 // `resize` sits in "+N"
    h.model.toggleRun(resize)
    #expect(await waitUntil { h.notch.calls.contains("flash(exclamationmark)") })
    #expect(h.model.isOnScreenAsTile(.shortcut(morning.id)))
    #expect(!h.model.isOnScreenAsTile(.shortcut(resize.id)))
    h.model.withdrawTiles(of: launcher)                                    // the page changed
    #expect(!h.model.isOnScreenAsTile(.shortcut(morning.id)))
    h.notch.emit(.closed)
    h.model.present([.shortcut(morning.id)], by: launcher)
    #expect(!h.model.isOnScreenAsTile(.shortcut(morning.id)))              // a closed panel shows no tile
    h.model.stop()
}

@Test func resultsNobodyCanSeeAreAnnouncedAtMostOncePer10Seconds() async {
    let h = ModelHarness(apps: [], shortcuts: [morning, resize], cli: FakeCLI(listing: shortcutListFixture))
    await h.model.start()
    h.model.toggleRun(morning)                                             // closed: flash + announcement
    h.model.toggleRun(resize)                                              // within 10 s: flash only
    #expect(await waitUntil { h.notch.calls.filter { $0 == "flash(checkmark.circle.fill)" }.count == 2 })
    #expect(h.announced.messages.count == 1)
    #expect(h.announced.messages.first?.contains("Morning routine") == true
            || h.announced.messages.first?.contains("Resize images") == true)
    h.model.stop()
}

@Test func aResultOnAVisibleTileIsNotAnnounced() async {
    let h = ModelHarness(apps: [], shortcuts: [morning], cli: FakeCLI(listing: shortcutListFixture))
    await h.model.start()
    h.notch.emit(.opened(.click))
    h.model.present([.shortcut(morning.id)], by: UUID())
    h.model.toggleRun(morning)
    #expect(await waitUntil { h.model.runs.state(of: morning.id) == .succeeded })
    #expect(h.announced.messages.isEmpty)                                  // the tile and its value show it
    #expect(!h.notch.calls.contains { $0.hasPrefix("flash") })
    h.model.stop()
}

@Test func demoModeAnnouncesNoShortcutName() async {
    let h = ModelHarness(apps: [], shortcuts: [morning], cli: FakeCLI(listing: shortcutListFixture))
    await h.model.start()
    h.environment.isDemoMode = true
    h.model.toggleRun(morning)
    #expect(await waitUntil { h.announced.messages.count == 1 })
    #expect(h.announced.messages.first?.contains("Morning") == false)
    #expect(h.model.publicName(of: morning) == QuickAppsModel.neutralShortcutName)
    h.model.stop()
}

// MARK: - Announcements are for runs the user started (DESIGN.md §16)

@Test func nothingRunsAShortcutByItself() async {
    // Launch, panel events, the palette and the list refreshes never run a shortcut: every run, and so every result
    // that is flashed or announced, comes from a user's action (`activate` / `toggleRun`).
    let h = ModelHarness(apps: [], shortcuts: [morning, resize], cli: FakeCLI(listing: shortcutListFixture))
    await h.model.start()
    for event in [NotchEvent.opened(.click), .paletteOpened, .pinned(true), .pinned(false), .closed] { h.notch.emit(event) }
    h.model.prepareShortcutList()
    #expect(await waitUntil { h.cli.calls.contains { $0.first == "list" } })
    h.model.stop()
    #expect(!h.cli.calls.contains { $0.first == "run" })
    #expect(h.announced.messages.isEmpty)
    #expect(!h.notch.calls.contains { $0.hasPrefix("flash") })
}

@Test func aRunTheUserStopsIsNeitherFlashedNorAnnounced() async {
    let h = ModelHarness(apps: [], shortcuts: [morning], cli: FakeCLI(listing: shortcutListFixture, runDuration: .seconds(30)))
    await h.model.start()
    h.model.toggleRun(morning)
    #expect(h.model.runs.isRunning(morning.id))
    h.model.toggleRun(morning)                                             // stop: the same tile, menu or ⌘K entry
    #expect(await waitUntil { h.model.runs.state(of: morning.id) == .idle })
    #expect(h.announced.messages.isEmpty)
    #expect(!h.notch.calls.contains { $0.hasPrefix("flash") })
    h.model.stop()
}

@Test func aShortcutResultSharesTheAppWideAnnouncementLimit() async {
    // `services.announcer` is one limit for the whole app: a P1 alert announced by another module a moment earlier
    // leaves the shortcut's result to the notch flash.
    let h = ModelHarness(apps: [], shortcuts: [morning], cli: FakeCLI(listing: shortcutListFixture))
    await h.model.start()
    #expect(h.services.announcer.announce("Timer done", kind: .alert))
    h.model.toggleRun(morning)
    #expect(await waitUntil { h.notch.calls.contains("flash(checkmark.circle.fill)") })
    #expect(h.announced.messages == ["Timer done"])
    h.model.stop()
}

@Test func aFailedShortcutMissingFromShortcutsSaysSo() async {
    let deleted = ShortcutEntry(id: "DDDDDDDD-DDDD-4DDD-8DDD-DDDDDDDDDDDD", name: "Deleted")
    let h = ModelHarness(apps: [], shortcuts: [deleted], cli: FakeCLI(listing: shortcutListFixture, failing: [deleted.id]))
    await h.model.start()
    h.model.toggleRun(deleted)
    #expect(await waitUntil { h.model.runs.state(of: deleted.id) == .failed(.shortcutNotFound) })
    #expect(h.notch.calls.contains("flash(exclamationmark)"))
    h.model.stop()
}

@Test func clickingARunningShortcutStopsIt() async {
    let h = ModelHarness(apps: [], shortcuts: [morning], cli: FakeCLI(runDuration: .seconds(30)))
    await h.model.start()
    h.model.toggleRun(morning)
    #expect(h.model.runs.isRunning(morning.id))
    h.model.toggleRun(morning)
    #expect(await waitUntil { h.model.runs.state(of: morning.id) == .idle })
    #expect(!h.notch.calls.contains { $0.hasPrefix("flash") })
    h.model.stop()
}

@Test func closingThePanelEndsEditMode() async {
    let h = ModelHarness()
    await h.model.start()
    h.model.isEditing = true
    h.notch.emit(.opened(.hover))
    #expect(h.model.isPanelOpen && h.model.isEditing)
    h.notch.emit(.closed)
    #expect(!h.model.isPanelOpen && !h.model.isEditing)
    h.model.stop()
}

@Test func openingThePaletteRefreshesTheShortcutList() async {
    let fake = FakeCLI(listing: shortcutListFixture)
    let h = ModelHarness(cli: fake)
    await h.model.start()
    #expect(fake.calls.isEmpty)                                            // nothing read at launch
    h.notch.emit(.paletteOpened)
    #expect(await waitUntil { h.model.shortcutsCatalog.shortcuts.count == 9 })
    h.notch.emit(.paletteOpened)                                           // fresh: not read again
    try? await Task.sleep(for: .milliseconds(30))
    #expect(fake.calls.count == 1)
    h.model.stop()
}

@Test func renamedShortcutsKeepTheirTileAndTakeTheNewName() async {
    let renamed = ShortcutEntry(id: morning.id, name: "Old name", symbol: "bolt.fill", tint: .teal)
    let h = ModelHarness(apps: [], shortcuts: [renamed], cli: FakeCLI(listing: shortcutListFixture))
    await h.model.start()
    await h.model.shortcutsCatalog.refresh()
    #expect(await waitUntil { h.model.shortcutEntries.first?.name == "Morning routine" })
    #expect(h.model.shortcutEntries.first?.symbol == "bolt.fill")
    #expect(h.model.shortcutEntries.first?.tint == .teal)
    h.model.stop()
}

@Test func addingAppsDeduplicates() async {
    let h = ModelHarness(installed: ["a"], apps: ["a"])
    await h.model.start()
    let added = await h.model.addApps(at: ["/x/b.app", "/x/a.app", "/x/b.app", "/x/notes.txt"].map { URL(fileURLWithPath: $0) })
    #expect(added == 1)
    #expect(h.model.appEntries.map(\.bundleID) == ["a", "b"])
    #expect(h.model.tiles.map(\.id) == [.app("a"), .app("b")])           // shown before the next lookup
    h.model.stop()
}

@Test func addingAndStylingShortcuts() {
    let h = ModelHarness(apps: [])
    h.model.add(shortcut: ShortcutInfo(id: morning.id, name: morning.name))
    h.model.add(shortcut: ShortcutInfo(id: morning.id, name: "again"))
    #expect(h.model.shortcutEntries == [morning])
    #expect(h.model.isAdded(shortcut: morning.id))
    h.model.setAppearance(of: morning.id, symbol: "star.fill", tint: .pink)
    #expect(h.model.shortcutEntries.first?.symbol == "star.fill")
    #expect(h.model.shortcutEntries.first?.tint == .pink)
    h.model.setAppearance(of: morning.id, symbol: nil, tint: nil)
    #expect(h.model.shortcutEntries == [morning])
}

@Test func removingATilePrunesTheOrder() async {
    let h = ModelHarness(installed: ["a", "b"], apps: ["a", "b"], shortcuts: [morning])
    await h.model.start()
    h.model.move(.shortcut(morning.id), toVisibleIndex: 0)
    #expect(h.services.settings[QuickAppsSettings.order] == ["shortcut:\(morning.id)", "app:a", "app:b"])
    h.model.remove(.shortcut(morning.id))
    #expect(h.model.shortcutEntries.isEmpty)
    #expect(h.services.settings[QuickAppsSettings.order] == ["app:a", "app:b"])
    h.model.remove(.app("a"))
    #expect(h.model.tiles.map(\.id) == [.app("b")])
    h.model.stop()
}

@Test func reorderingInTheWidgetAndInSettings() async {
    let h = ModelHarness(installed: ["a", "c"], apps: ["a", "hidden", "c"], shortcuts: [morning])
    await h.model.start()
    h.model.move(.shortcut(morning.id), toVisibleIndex: 1)                // visible: a, S, c
    #expect(h.model.tiles.map(\.id) == [.app("a"), .shortcut(morning.id), .app("c")])
    #expect(h.model.arrangement == [.app("a"), .app("hidden"), .shortcut(morning.id), .app("c")])
    h.model.move(.app("c"), by: -10)                                        // Settings: Move Up past the top
    #expect(h.model.arrangement.first == .app("c"))
    h.model.move(fromOffsets: IndexSet(integer: 0), toOffset: 4)            // List.onMove: first to the end
    #expect(h.model.arrangement.last == .app("c"))
    let before = h.services.settings[QuickAppsSettings.order]
    h.model.move(.app("a"), toVisibleIndex: 0)                              // no-op move writes nothing
    #expect(h.services.settings[QuickAppsSettings.order] == before)
    h.model.stop()
}

@Test func anAppInstalledLaterAppearsWhenItLaunches() async {
    let h = ModelHarness(installed: [], apps: ["a"])
    await h.model.start()
    #expect(h.model.catalog.isMissing("a"))
    #expect(h.model.tiles.isEmpty)
    h.resolver.install("a")
    h.model.running.onLaunch?("a")                                        // what a didLaunch notification calls
    #expect(await waitUntil { h.model.tiles.map(\.id) == [.app("a")] })
    h.model.stop()
}

@Test func stopCancelsRunningShortcuts() async {
    let h = ModelHarness(apps: [], shortcuts: [morning], cli: FakeCLI(runDuration: .seconds(30)))
    await h.model.start()
    h.model.toggleRun(morning)
    h.model.stop()
    #expect(await waitUntil { !h.model.runs.hasRunningShortcuts })
}

@Test func droppingAppsOnTheLauncherAddsThem() async {
    let h = ModelHarness(installed: ["a"], apps: ["a"])
    await h.model.start()
    let apps = DropPayload(fileURLs: ["/Applications/b.app", "/Applications/a.app"].map { URL(fileURLWithPath: $0) },
                           contentTypes: [.applicationBundle])
    #expect(await h.model.acceptDrop(apps))
    #expect(h.model.appEntries.map(\.bundleID) == ["a", "b"])
    // Not an app: left for the shell's fallback (the Tray).
    let document = DropPayload(fileURLs: [URL(fileURLWithPath: "/tmp/notes.txt")], contentTypes: [.plainText])
    #expect(await h.model.acceptDrop(document) == false)
    h.model.stop()
}

@Test func aDropOfAppsAndDocumentsGoesWhollyToTheTray() async {
    // Regression: the app was added and the documents silently dropped (a true return skips the Tray fallback).
    let h = ModelHarness(installed: ["a"], apps: ["a"])
    await h.model.start()
    let mixed = DropPayload(fileURLs: [URL(fileURLWithPath: "/Applications/b.app"), URL(fileURLWithPath: "/tmp/notes.txt")],
                            contentTypes: [.applicationBundle, .plainText])
    #expect(await h.model.acceptDrop(mixed) == false)
    #expect(h.model.appEntries.map(\.bundleID) == ["a"])                   // nothing added: one place for one drop
    #expect(await h.model.acceptDrop(DropPayload(fileURLs: [], contentTypes: [])) == false)
    h.model.stop()
}

@Test func onlyAnAppOnlyDragArmsTheAddOverlay() {
    #expect(QuickAppsModel.dragAddsApps([.applicationBundle]))
    #expect(QuickAppsModel.dragAddsApps([.fileURL, .applicationBundle]))   // generic file-drag types do not count
    #expect(QuickAppsModel.dragAddsApps([.item, .application]))
    #expect(!QuickAppsModel.dragAddsApps([.applicationBundle, .plainText]))
    #expect(!QuickAppsModel.dragAddsApps([.fileURL]))
    #expect(!QuickAppsModel.dragAddsApps([.folder]))
    #expect(!QuickAppsModel.dragAddsApps([]))
}

@Test func aShortcutRunFromThePaletteFlashesEvenWhileOpen() async {
    // Not on the launcher, so no tile can show the result.
    let other = ShortcutEntry(id: "7F6E5D4C-3B2A-4190-8F7E-6D5C4B3A2905", name: "Clean Desktop")
    let h = ModelHarness(apps: [], shortcuts: [])
    await h.model.start()
    h.notch.emit(.opened(.keyboard))
    h.model.toggleRun(other)
    #expect(await waitUntil { h.notch.calls.contains("flash(checkmark.circle.fill)") })
    h.model.stop()
}
