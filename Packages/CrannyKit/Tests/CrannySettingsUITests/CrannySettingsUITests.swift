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
