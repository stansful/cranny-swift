import CrannyCore
import SwiftUI
import Testing
@testable import CrannySettingsUI

@Test func sidebarListsEveryShellPaneInDesignOrder() {
    let root = SettingsRootView(registry: ModuleRegistry(services: .preview()))
    #expect(root.pages.map(\.id) == [.general, .appearance, .keyboard, .nookAndWidgets, .liveActivities, .gestures,
                                     .permissions, .about])
    #expect(root.pages.filter { $0.previewState == nil }.map(\.id) == [.permissions, .about])   // no preview stage
    #expect(!root.pages.contains { $0.title.contains("Nook") })                                  // D20: never in UI text
}

@Test func modulePanesSortIntoTheirGroupsAndAreSearchable() {
    let registry = ModuleRegistry(services: .preview())
    registry.add(settingsPage: SettingsPage(id: .hud, title: "HUD", symbol: "speaker.wave.2.fill", tint: .teal, group: .notch,
                                            order: 2, keywords: ["volume", "brightness"]) { AnyView(EmptyView()) })
    let pages = SettingsRootView(registry: registry).pages
    #expect(pages.map(\.id).firstIndex(of: .hud) == pages.map(\.id).firstIndex(of: .gestures).map { $0 - 1 })
    #expect(SettingsSearch.filter(pages, query: "VOLUME").map(\.id) == [.hud])
    #expect(SettingsSearch.filter(pages, query: "  ").count == pages.count)
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

    settings[CoreSettings.notchFit] = ["1552-41001": NotchFit(widthTune: 2, radiusTune: 1)]
    settings[CoreSettings.includesPrereleases] = true
    settings[CoreSettings.displaySelection] = .all
    for namespace in general.namespaces { settings.reset(module: namespace) }
    #expect(!settings[CoreSettings.includesPrereleases] && settings[CoreSettings.displaySelection] == .builtIn)
    #expect(settings[CoreSettings.notchFit]["1552-41001"]?.widthTune == 2)        // the calibration is Appearance's
    for namespace in appearance.namespaces { settings.reset(module: namespace) }
    #expect(settings[CoreSettings.notchFit].isEmpty)
}
