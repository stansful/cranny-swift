import CrannyCore
import SwiftUI
import Testing
@testable import CrannySettingsUI

// MARK: - Sidebar and panes

@Test func sidebarListsEveryShellPaneInDesignOrder() {
    let root = SettingsRootView(registry: ModuleRegistry(services: .preview()))
    #expect(root.pages.map(\.id) == [.general, .appearance, .keyboard, .nookAndWidgets, .liveActivities, .gestures,
                                     .permissions, .about])
    #expect(root.pages.filter { $0.previewState == nil }.map(\.id) == [.permissions, .about])   // no preview stage
    #expect(!root.pages.contains { $0.title.contains("Nook") })                                  // D20: never in UI text
}

@Test func panesAutoSelectTheirStageState() {
    let pages = ShellPanes.all(registry: ModuleRegistry(services: .preview()))
    let states = Dictionary(uniqueKeysWithValues: pages.map { ($0.id, StageScript.initialState(for: $0)) })
    #expect(states[.general] == .closed)
    #expect(states[.appearance] == .open)
    #expect(states[.nookAndWidgets] == .open)
    #expect(states[.liveActivities] == .activity)
    #expect(StageScript.initialState(for: nil) == .closed)
}

@Test func modulePanesSortIntoTheirGroups() {
    let registry = ModuleRegistry(services: .preview())
    registry.add(settingsPage: SettingsPage(id: .hud, title: "HUD", symbol: "speaker.wave.2.fill", tint: .teal, group: .notch,
                                            order: 2, keywords: ["volume", "brightness"]) { AnyView(EmptyView()) })
    let ids = SettingsRootView(registry: registry).pages.map(\.id)
    #expect(ids.firstIndex(of: .hud) == ids.firstIndex(of: .gestures).map { $0 - 1 })
}

/// "Reset ‹Pane›…" resets exactly the namespaces of the rows the pane shows (DESIGN.md §11.1).
@Test func paneResetsCoverTheirOwnRows() throws {
    let registry = ModuleRegistry(services: .preview())
    let settings = registry.services.settings
    let panes = ShellPanes.all(registry: registry)
    let general = try #require(panes.first { $0.id == .general })
    let appearance = try #require(panes.first { $0.id == .appearance })
    #expect(general.namespaces == [.general, .displays, .updates])               // Updates rows live in General
    #expect(appearance.namespaces == [.appearance])
    #expect(panes.first { $0.id == .permissions }?.namespaces == [])
    #expect(panes.first { $0.id == .about }?.namespaces == [])

    settings[CoreSettings.notchFit] = ["1552-41001": NotchFit(widthTune: 2, radiusTune: 1)]
    settings[CoreSettings.includesPrereleases] = true
    settings[CoreSettings.displaySelection] = .all
    PaneReset.reset(general.namespaces, settings: settings)
    #expect(!settings[CoreSettings.includesPrereleases] && settings[CoreSettings.displaySelection] == .builtIn)
    #expect(settings[CoreSettings.notchFit]["1552-41001"]?.widthTune == 2)        // the calibration is Appearance's
    PaneReset.reset(appearance.namespaces, settings: settings)
    #expect(settings[CoreSettings.notchFit].isEmpty)
}

/// "Reset Live Activities…" must not resume activities the menu bar paused, and "Reset General…" keeps the record
/// of the last update check; both are records sharing a namespace, not preferences the pane shows.
@Test func paneResetsKeepThePauseAndTheLastUpdateCheck() async throws {
    let registry = ModuleRegistry(services: .preview())
    let settings = registry.services.settings
    let panes = ShellPanes.all(registry: registry)
    let activities = try #require(panes.first { $0.id == .liveActivities })
    let general = try #require(panes.first { $0.id == .general })
    let until = Date().addingTimeInterval(3600)
    let checked = Date().addingTimeInterval(-600)
    settings[CoreSettings.pausedUntil] = until
    settings[CoreSettings.lastUpdateCheck] = checked
    settings[CoreSettings.satellite] = false
    settings[CoreSettings.checksForUpdates] = false
    var pauses: [Date?] = []
    let token = observe({ settings[CoreSettings.pausedUntil] }) { pauses.append($0) }

    PaneReset.reset(activities.namespaces, settings: settings)
    PaneReset.reset(general.namespaces, settings: settings)
    #expect(settings[CoreSettings.satellite] && settings[CoreSettings.checksForUpdates])      // the pane's rows reset
    #expect(settings[CoreSettings.pausedUntil] == until)
    #expect(settings[CoreSettings.lastUpdateCheck] == checked)
    for _ in 0..<20 { await Task.yield() }
    #expect(pauses.isEmpty)                                                                     // observers never saw a resume
    token.cancel()

    settings.resetAll()                                                                         // Reset All still clears them
    #expect(settings[CoreSettings.pausedUntil] == nil && settings[CoreSettings.lastUpdateCheck] == nil)
}

// MARK: - Rows

@Test func rowsAreUniqueLocalizedAndNeverSayNook() {
    let registry = ModuleRegistry(services: .preview())
    registry.add(shortcut: GlobalShortcut(id: .openNook, title: "Open Cranny", defaultCombo: .openNookDefault) {})
    registry.declare(.calendar, reason: "Show your events in Cranny.")
    let rows = ShellPanes.rows(registry: registry)
    #expect(Set(rows.map(\.id)).count == rows.count)
    #expect(rows.allSatisfy { !$0.title.isEmpty && $0.id.hasPrefix($0.pane.rawValue + ".") })
    let text = rows.flatMap { [$0.title] + $0.keywords }
    #expect(!text.contains { $0.localizedCaseInsensitiveContains("nook") })
    let panes = Set(ShellPanes.all(registry: registry).map(\.id))
    #expect(rows.allSatisfy { panes.contains($0.pane) })
}

@Test func keyboardRowsFollowTheDesignOrder() {
    let ids: [ShortcutID] = ["module.other", .togglePin, .newNote, .openNook, .pauseActivities, .openTray, .startTimer]
    let shortcuts = ids.map { GlobalShortcut(id: $0, title: $0.rawValue) {} }
    #expect(KeyboardRows.ordered(shortcuts).map(\.id)
            == [.openNook, .openTray, .newNote, .startTimer, .togglePin, .pauseActivities, "module.other"])
}

@Test func effectiveShortcutPrefersTheUsersBinding() {
    let settings = CrannyServices.preview().settings
    let shortcut = GlobalShortcut(id: .openNook, title: "Open Cranny", defaultCombo: .openNookDefault) {}
    #expect(KeyboardRows.effectiveCombo(shortcut, settings: settings) == .openNookDefault)
    let custom = KeyCombo(keyCode: 46, modifiers: [.control, .option], display: "⌃⌥M")
    settings[CoreSettings.shortcuts][.openNook] = .some(custom)
    #expect(KeyboardRows.effectiveCombo(shortcut, settings: settings) == custom)
    settings[CoreSettings.shortcuts][.openNook] = .some(nil)                     // explicitly off
    #expect(KeyboardRows.effectiveCombo(shortcut, settings: settings) == nil)
    settings[CoreSettings.shortcuts][.openNook] = nil                            // Reset to Default
    #expect(KeyboardRows.effectiveCombo(shortcut, settings: settings) == .openNookDefault)
}

@Test func captureTargetsMergeRegisteredTitles() {
    let registry = ModuleRegistry(services: .preview())
    registry.add(captureTarget: CaptureTarget(id: "todos", title: "My to-dos", symbol: "checklist") { _ in .todos })
    registry.add(captureTarget: CaptureTarget(id: "journal", title: "Journal", symbol: "note.text") { _ in .notes })
    let targets = KeyboardRows.captureTargets(registry)
    #expect(targets.map(\.id) == ["notes", "todos", "journal"])
    #expect(targets[1].title == "My to-dos")
}

// MARK: - Formatting and small helpers

@Test func valuesCarryTheirUnits() {
    let en = Locale(identifier: "en_US")
    #expect(SettingsFormat.signedNumber(0, locale: en) == "±0")
    #expect(SettingsFormat.signedNumber(2, locale: en) == "+2")
    #expect(SettingsFormat.signedNumber(-1.5, locale: en) == "\u{2212}1.5")
    #expect(SettingsFormat.signedNumber(0.04, locale: en) == "±0")
    #expect(SettingsFormat.milliseconds(0.12, locale: en).hasPrefix("120"))
    #expect(SettingsFormat.seconds(10, locale: en).hasPrefix("10"))
    #expect(SettingsFormat.seconds(2.6, locale: en).hasPrefix("2.6"))
    #expect(SettingsFormat.percent(1, locale: en) == "100%")
}

@Test func notchFitDetentFiresOnReachingOrCrossingZero() {
    #expect(NotchFitControls.crossesZero(from: -0.5, to: 0))
    #expect(NotchFitControls.crossesZero(from: 1, to: -1))
    #expect(NotchFitControls.crossesZero(from: 0.5, to: 0))
    #expect(NotchFitControls.crossesZero(from: -1, to: 1))
    #expect(!NotchFitControls.crossesZero(from: 0, to: 0.5))
    #expect(!NotchFitControls.crossesZero(from: 0, to: -0.5))                // leaving 0 is silent on both sides
    #expect(!NotchFitControls.crossesZero(from: -2, to: -1))
    #expect(!NotchFitControls.crossesZero(from: 1, to: 2))
    #expect(!NotchFitControls.crossesZero(from: 0, to: 0))
}

@Test func showOnModesMapToSelections() {
    let keys: [DisplayKey] = ["A", "B"]
    #expect(DisplayMode(.custom(["A"])) == .custom)
    #expect(DisplayMode.custom.selection(current: .builtIn, shown: keys) == .custom(keys))
    #expect(DisplayMode.custom.selection(current: .custom(["B"]), shown: keys) == .custom(["B"]))   // keeps the list
    #expect(DisplayMode.pointer.selection(current: .custom(["B"]), shown: keys) == .pointer)
}

/// "Chosen displays" never ends up with no connected display checked: the last one stays, and when every chosen
/// display is unplugged the shell's fallback is named.
@Test func chosenDisplaysKeepOneConnectedDisplay() {
    let connected: [DisplayKey] = ["A", "B"]
    #expect(ChosenDisplays.connected(.custom(["B", "X"]), connected: connected) == ["B"])
    #expect(ChosenDisplays.isLast("B", in: .custom(["B", "X"]), connected: connected))       // X is not connected
    #expect(!ChosenDisplays.isLast("A", in: .custom(["A", "B"]), connected: connected))
    #expect(!ChosenDisplays.isLast("A", in: .custom(["B"]), connected: connected))            // not in the list
    #expect(!ChosenDisplays.isLast("A", in: .all, connected: connected))
    #expect(ChosenDisplays.connected(.custom(["X"]), connected: connected).isEmpty)           // → the fallback footnote
}

/// Search offers Glass island only where the pane shows it (macOS 26 and later).
@Test func searchOffersOnlyRowsThePaneShows() {
    #expect(!AppearanceRows.rows(includingGlassIsland: false).contains { $0.id == AppearanceRows.glassIsland.id })
    #expect(AppearanceRows.rows(includingGlassIsland: true).contains { $0.id == AppearanceRows.glassIsland.id })
    #expect(AppearanceRows.all.contains { $0.id == AppearanceRows.glassIsland.id } == AppearanceRows.hasGlassIsland)
    let registry = ModuleRegistry(services: .preview())
    let index = SettingsSearchIndex(pages: SettingsRootView.pages(registry: registry), rows: ShellPanes.rows(registry: registry))
    #expect(index.search("glass").rows.isEmpty == !AppearanceRows.hasGlassIsland)
}

/// The composed labels go through one localized pattern each (the same in English and Russian).
@Test func composedLabelsUseOneLocalizedPattern() {
    #expect(SettingsFormat.pair("Media", "Studio Display") == "Media, Studio Display")
    #expect(LayoutRows.width(of: "Media", cells: 1) == SettingsFormat.pair("Media", LayoutRows.cells(1)))
    #expect(SettingsFormat.detailed("Song and artist", "4–6") == "Song and artist · 4–6")
}

@Test func permissionsGroupByKindInDesignOrder() {
    let uses = [PermissionUse(kind: .bluetooth, module: .system, reason: "B"),
                PermissionUse(kind: .calendar, module: .calendar, reason: "C1"),
                PermissionUse(kind: .calendar, module: .calendar, reason: "C1"),
                PermissionUse(kind: .calendar, module: .timer, reason: "C2"),
                PermissionUse(kind: .accessibility, module: .hud, reason: "A")]
    let entries = PermissionEntry.entries(uses)
    #expect(entries.map(\.kind) == [.calendar, .accessibility, .bluetooth])
    #expect(entries[0].reasons == ["C1", "C2"])
}

@Test func permissionButtonsNeverPromptUnasked() {
    #expect(PermissionAction(kind: .calendar, status: .notDetermined) == .grant)
    #expect(PermissionAction(kind: .systemAudioRecording, status: .notDetermined) == .openSettings)   // no request API
    #expect(PermissionAction(kind: .camera, status: .denied) == .openSettings)
    #expect(PermissionAction(kind: .automation(bundleID: "com.apple.Music"), status: .unknown) == .openSettings)
    #expect(PermissionAction(kind: .camera, status: .granted) == nil)
}
