import CrannyCore
import Foundation
import Testing
@testable import CrannySettingsUI

// MARK: - Settings ▸ Keyboard: type to capture with its widget on no page (ARCHITECTURE §10.20 issue 7)

private func captureRegistry() -> ModuleRegistry {
    let registry = ModuleRegistry(services: .preview())
    registry.add(captureTarget: CaptureTarget(id: "notes", title: "Notes", symbol: "note.text", widget: .notes) { _ in .notes })
    registry.add(captureTarget: CaptureTarget(id: "todos", title: "To-dos", symbol: "checklist", widget: .todos) { _ in .todos })
    return registry
}

/// The default Home (Media, Calendar, Quick Apps) has no Notes, so the default target captures nothing: warn.
@Test func captureWarnsWhileItsWidgetIsOnNoPage() {
    let registry = captureRegistry()
    let settings = registry.services.settings
    #expect(settings[CoreSettings.typeToCapture] == "notes")
    #expect(KeyboardRows.captureGap(registry) == KeyboardRows.CaptureGap(widget: .notes, title: "Notes"))

    settings[CoreSettings.typeToCapture] = "todos"
    #expect(KeyboardRows.captureGap(registry) == KeyboardRows.CaptureGap(widget: .todos, title: "To-dos"))
}

/// Any grid page counts, as in the shell (`KeyboardRouter.captureTarget()`): Home or a user page.
@Test func captureIsQuietOnceItsWidgetIsOnAnyPage() {
    let registry = captureRegistry()
    let settings = registry.services.settings
    settings[CoreSettings.pages] = [NookPreset.maker.page]                                       // Notes on Home
    #expect(KeyboardRows.captureGap(registry) == nil)

    let user = NookPage(id: "page.user", symbol: "checklist", items: [NookItem(.todos, cells: 3)])
    settings[CoreSettings.pages] = [NookPreset.listener.page, user]                              // To-dos on a user page
    settings[CoreSettings.typeToCapture] = "todos"
    #expect(KeyboardRows.captureGap(registry) == nil)
    settings[CoreSettings.typeToCapture] = "notes"
    #expect(KeyboardRows.captureGap(registry)?.widget == .notes)
}

/// Off, an unknown target and a target that names no widget (always captured) never warn.
@Test func captureWarnsOnlyForATargetThatNamesItsWidget() {
    let registry = captureRegistry()
    registry.add(captureTarget: CaptureTarget(id: "journal", title: "Journal", symbol: "note.text") { _ in .notes })
    let settings = registry.services.settings
    settings[CoreSettings.typeToCapture] = nil
    #expect(KeyboardRows.captureGap(registry) == nil)
    settings[CoreSettings.typeToCapture] = "journal"
    #expect(KeyboardRows.captureGap(registry) == nil)
    settings[CoreSettings.typeToCapture] = "unregistered"
    #expect(KeyboardRows.captureGap(registry) == nil)
    #expect(KeyboardRows.captureGap(ModuleRegistry(services: .preview())) == nil)                // no module registered one
}

/// "Show in Layout & Widgets" lands on the widget's library entry: the same id the library row is a search target by.
@Test func captureWarningLeadsToTheWidgetsLibraryEntry() {
    let row = LayoutRows.widget(.notes, title: "Notes")
    #expect(row.pane == .nookAndWidgets)
    let deepLink = SettingsNavigator.parse(SettingsPageID("nook#widget.\(WidgetID.notes.rawValue)"))
    #expect(deepLink.pane == .nookAndWidgets && deepLink.row == row.id)
}
