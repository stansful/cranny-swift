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
    for namespace in general.namespaces { settings.reset(module: namespace) }
    #expect(!settings[CoreSettings.includesPrereleases] && settings[CoreSettings.displaySelection] == .builtIn)
    #expect(settings[CoreSettings.notchFit]["1552-41001"]?.widthTune == 2)        // the calibration is Appearance's
    for namespace in appearance.namespaces { settings.reset(module: namespace) }
    #expect(settings[CoreSettings.notchFit].isEmpty)
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
    #expect(!NotchFitControls.crossesZero(from: 0, to: 0.5))
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
