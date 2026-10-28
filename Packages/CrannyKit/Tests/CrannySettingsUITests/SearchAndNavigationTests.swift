import CrannyCore
import SwiftUI
import Testing
@testable import CrannySettingsUI

private func modulePage(_ id: SettingsPageID, _ title: String, group: SettingsGroup = .features, keywords: [String] = []) -> SettingsPage {
    SettingsPage(id: id, title: title, symbol: "gearshape.fill", tint: .gray, group: group, order: 0, keywords: keywords) { AnyView(EmptyView()) }
}

private func index(_ extra: [SettingsPage] = [], aliases: [SettingsPageID: [String]] = KnownPaneKeywords.all) -> SettingsSearchIndex {
    let registry = ModuleRegistry(services: .preview())
    for page in extra { registry.add(settingsPage: page) }
    return SettingsSearchIndex(pages: SettingsRootView.pages(registry: registry), rows: ShellPanes.rows(registry: registry), aliases: aliases)
}

// MARK: - Search (DESIGN.md §11.3)

@Test func volumeFindsTheHUDPaneEvenWithoutModuleKeywords() {
    let results = index([modulePage(.hud, "HUD", group: .notch)]).search("volume")
    #expect(results.panes == [.hud])
}

@Test func moduleKeywordsMatchInTheirOwnLanguage() {
    // A module lists localized keywords; in Russian the HUD pane declares «громкость».
    let results = index([modulePage(.hud, "HUD", group: .notch, keywords: ["громкость", "яркость"])], aliases: [:]).search("Громк")
    #expect(results.panes == [.hud])
}

@Test func rowLabelsAndKeywordsFindRows() {
    let search = index()
    #expect(search.search("hover delay").rows.map(\.id) == [GeneralRows.hoverDelay.id])
    #expect(search.search("ext mon").rows.map(\.id).contains(GeneralRows.showOn.id))      // word prefixes, any order
    #expect(search.search("external monitor").panes.contains(.general))                    // the pane of a matching row
    #expect(search.search("calibrate").rows.map(\.pane) == [.appearance])
}

/// Appearance ▸ Quality (the ambient light's Detailed / Efficient) sits under Effect and is found by its label, by its
/// options and by what Efficient saves (memory) or tunes (performance).
@Test func qualityRowIsListedAndFound() throws {
    let rows = AppearanceRows.all.map(\.id)
    let effect = try #require(rows.firstIndex(of: AppearanceRows.effect.id))
    #expect(rows.firstIndex(of: AppearanceRows.ambientDetail.id) == effect + 1)
    #expect(AppearanceRows.ambientDetail.id == "appearance.ambientDetail")
    let search = index()
    #expect(search.search("quality").rows.map(\.id) == [AppearanceRows.ambientDetail.id])
    #expect(search.search("memory").rows.map(\.id) == [AppearanceRows.ambientDetail.id])
    #expect(search.search("perf").panes.contains(.appearance))
    #expect(search.search("effic").rows.map(\.id) == [AppearanceRows.ambientDetail.id], "by the option's name")
}

@Test func aliasesApplyOnlyToRegisteredPanes() {
    #expect(index().search("dock").panes.isEmpty)
    #expect(index([modulePage(.shortcuts, "Shortcuts")]).search("dock").panes == [.shortcuts])
}

@Test func matchingFoldsCaseAndDiacriticsAndNeedsWordStarts() {
    let words = SettingsSearchIndex.words(in: ["Ёлка", "Reset All Settings…"])
    #expect(SettingsSearchIndex.matches(words, SettingsSearchIndex.words(in: ["елк"])))
    #expect(SettingsSearchIndex.matches(words, SettingsSearchIndex.words(in: ["SETT"])))
    #expect(!SettingsSearchIndex.matches(words, SettingsSearchIndex.words(in: ["ttings"])))
    #expect(!SettingsSearchIndex.matches(words, SettingsSearchIndex.words(in: ["reset", "nothing"])))
}

@Test func emptyQueryListsEveryPaneAndNoRows() {
    let search = index()
    let results = search.search("   ")
    #expect(results.rows.isEmpty)
    #expect(results.panes.count == 8)
    #expect(search.search("zzzz").isEmpty)
}

// MARK: - Navigation and deep links

@Test func deepLinksNameAPaneAndARow() {
    #expect(SettingsNavigator.parse("general#hoverDelay") == ("general", "general.hoverDelay"))
    #expect(SettingsNavigator.parse("about") == ("about", nil))
    #expect(SettingsNavigator.parse("about#") == ("about", nil))
    #expect(SettingsNavigator.parse(nil) == (nil, nil))
}

@Test func navigatorScrollsOnlyTheRowsPane() {
    let navigator = SettingsNavigator(target: "appearance")
    #expect(navigator.selection == .appearance)
    navigator.open(row: GeneralRows.hoverDelay)
    #expect(navigator.selection == .general)
    #expect(navigator.highlightedRow == GeneralRows.hoverDelay.id && navigator.isHighlightFresh)
    #expect(navigator.takePendingRow(in: .appearance) == nil)                   // the old pane must not take it
    #expect(navigator.takePendingRow(in: .general) == GeneralRows.hoverDelay.id)
    #expect(navigator.takePendingRow(in: .general) == nil)                      // once
    let serial = navigator.highlightSerial
    navigator.open("keyboard")
    #expect(navigator.selection == .keyboard && navigator.highlightSerial == serial)
}

@Test func initialDeepLinkOpensThePaneAtTheRow() {
    let navigator = SettingsNavigator(target: "general#hoverDelay")
    #expect(navigator.selection == .general)
    #expect(navigator.takePendingRow(in: .general) == "general.hoverDelay")
}
