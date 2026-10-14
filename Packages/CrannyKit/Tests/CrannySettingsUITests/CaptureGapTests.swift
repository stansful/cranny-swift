import CrannyCore
import Foundation
import Testing
@testable import CrannySettingsUI

// MARK: - Settings ▸ Keyboard: type to capture with its widget on no page (ARCHITECTURE §10.20 issue 7)

/// Core's stand-ins carry the widgets' DESIGN.md §6.7 sizes (Notes 3–8, To-dos 2–6), so room is judged as in the app.
private func captureRegistry() -> ModuleRegistry {
    let registry = ModuleRegistry(services: .preview())
    registry.addPreviewStandIns()
    registry.add(captureTarget: CaptureTarget(id: "notes", title: "Notes", symbol: "note.text", widget: .notes) { _ in .notes })
    registry.add(captureTarget: CaptureTarget(id: "todos", title: "To-dos", symbol: "checklist", widget: .todos) { _ in .todos })
    return registry
}

/// The live pages at `maxColumns` (the stage's display decides it in the app).
private func layout(_ registry: ModuleRegistry, maxColumns: Int) -> LayoutEditor {
    let live = LayoutEditor.live(registry: registry, stage: nil)
    let sizes = Dictionary(uniqueKeysWithValues: registry.widgets.map { ($0.id, $0.sizes) })
    return LayoutEditor(pages: live.pages, maxColumns: maxColumns, sizes: sizes)
}

/// Ruling E2 (§10.20 #24): a fresh install has Type to capture off, so the default Home (Listener, no Notes) shows
/// no Keyboard warning.
@Test func aFreshInstallShowsNoKeyboardWarning() {
    let registry = captureRegistry()
    #expect(registry.services.settings[CoreSettings.typeToCapture] == nil)
    #expect(registry.services.settings[CoreSettings.pages] == [NookPreset.listener.page])
    #expect(KeyboardRows.captureGap(registry, layout: LayoutEditor.live(registry: registry, stage: nil)) == nil)
}

/// The default Home (Listener: Media 5, Calendar 3, Quick Apps 2) has no Notes, so Notes as the target captures
/// nothing: warn. On the reference 14-inch display (12 columns) Home has 2 cells left and Notes needs 3, so the way
/// out is a new page; with 13 columns Notes fits on Home and the warning leads to its library entry.
@Test func captureWarnsWhileItsWidgetIsOnNoPage() {
    let registry = captureRegistry()
    let settings = registry.services.settings
    settings[CoreSettings.typeToCapture] = "notes"                                       // chosen (an earlier install)
    let reference = LayoutEditor.live(registry: registry, stage: nil)
    #expect(reference.maxColumns == 12)                                                  // 1512-pt display, Standard
    let gap = KeyboardRows.captureGap(registry, layout: reference)
    #expect(gap == KeyboardRows.CaptureGap(widget: .notes, title: "Notes", needsPage: true))
    #expect(gap?.destination == LayoutRows.pages)

    let wide = KeyboardRows.captureGap(registry, layout: layout(registry, maxColumns: 13))
    #expect(wide == KeyboardRows.CaptureGap(widget: .notes, title: "Notes", needsPage: false))
    #expect(wide?.destination == LayoutRows.widget(.notes, title: "Notes"))

    settings[CoreSettings.typeToCapture] = "todos"                                       // To-dos needs 2: fits Home
    #expect(KeyboardRows.captureGap(registry, layout: reference) == KeyboardRows.CaptureGap(widget: .todos, title: "To-dos", needsPage: false))
}

/// Any grid page counts, as in the shell (`KeyboardRouter.captureTarget()`): Home or a user page.
@Test func captureIsQuietOnceItsWidgetIsOnAnyPage() {
    let registry = captureRegistry()
    let settings = registry.services.settings
    settings[CoreSettings.typeToCapture] = "notes"
    settings[CoreSettings.pages] = [NookPreset.maker.page]                                       // Notes on Home
    #expect(KeyboardRows.captureGap(registry, layout: layout(registry, maxColumns: 12)) == nil)

    let user = NookPage(id: "page.user", symbol: "checklist", items: [NookItem(.todos, cells: 3)])
    settings[CoreSettings.pages] = [NookPreset.listener.page, user]                              // To-dos on a user page
    settings[CoreSettings.typeToCapture] = "todos"
    #expect(KeyboardRows.captureGap(registry, layout: layout(registry, maxColumns: 12)) == nil)
    settings[CoreSettings.typeToCapture] = "notes"
    #expect(KeyboardRows.captureGap(registry, layout: layout(registry, maxColumns: 12))?.widget == .notes)
}

/// Off, an unknown target and a target that names no widget (always captured) never warn.
@Test func captureWarnsOnlyForATargetThatNamesItsWidget() {
    let registry = captureRegistry()
    registry.add(captureTarget: CaptureTarget(id: "journal", title: "Journal", symbol: "note.text") { _ in .notes })
    let settings = registry.services.settings
    let editor = layout(registry, maxColumns: 12)
    settings[CoreSettings.typeToCapture] = nil
    #expect(KeyboardRows.captureGap(registry, layout: editor) == nil)
    settings[CoreSettings.typeToCapture] = "journal"
    #expect(KeyboardRows.captureGap(registry, layout: editor) == nil)
    settings[CoreSettings.typeToCapture] = "unregistered"
    #expect(KeyboardRows.captureGap(registry, layout: editor) == nil)
    let bare = ModuleRegistry(services: .preview())                                              // no module registered one
    #expect(KeyboardRows.captureGap(bare, layout: .live(registry: bare, stage: nil)) == nil)
}

/// The warning's way out always ends in an Add that works (the review of #7: on a 12-column display the default
/// Home refused Notes with "1 cells over"). A page with room: the library entry, and Layout & Widgets shows that page.
/// No page with room: Pages, where the new page takes the widget. Every page full and none left to add: the library
/// entry, whose Add explains the overflow.
@Test func captureWarningLeadsToAnAddThatWorks() {
    let registry = captureRegistry()
    let settings = registry.services.settings
    settings[CoreSettings.typeToCapture] = "notes"

    // Home is full for Notes; Add there is refused, so the warning sends the user to add a page first.
    var editor = layout(registry, maxColumns: 12)
    #expect(editor.add(.notes, to: .nook) == .overflow(cells: 1))
    #expect(KeyboardRows.captureGap(registry, layout: editor)?.destination == LayoutRows.pages)
    guard case .success(let added) = editor.addPage(title: "Page 2", symbol: "sparkles") else { Issue.record("no page added"); return }
    #expect(editor.add(.notes, to: added) == nil)

    // A user page with room: the library entry, shown on that page (not on the full Home), where Add takes Notes.
    let roomy = NookPage(id: "page.roomy", symbol: "sparkles", items: [NookItem(.timer, cells: 2)])
    settings[CoreSettings.pages] = [NookPreset.listener.page, roomy]
    editor = layout(registry, maxColumns: 12)
    let gap = KeyboardRows.captureGap(registry, layout: editor)
    #expect(gap?.needsPage == false && gap?.destination == LayoutRows.widget(.notes, title: "Notes"))
    let shown = gap.flatMap { LayoutRows.widgetID(inRow: $0.destination.id) }.flatMap { editor.page(for: $0, preferring: .nook) }
    #expect(shown == roomy.id)
    #expect(editor.add(.notes, to: roomy.id) == nil)

    // Home and three user pages, all too full for Notes: no page can be added, so the library entry it is.
    let full = (1...3).map { NookPage(id: PageID("page.\($0)"), symbol: "sparkles", items: [NookItem(.media, cells: 6), NookItem(.files, cells: 5)]) }
    settings[CoreSettings.pages] = [NookPreset.listener.page] + full
    editor = layout(registry, maxColumns: 12)
    #expect(!editor.canAddPage && !editor.hasRoom(for: .notes))
    #expect(KeyboardRows.captureGap(registry, layout: editor) == KeyboardRows.CaptureGap(widget: .notes, title: "Notes", needsPage: false))
}

/// Both destinations are deep links the navigator reads back (the button's path from previews and `--qa-settings`).
@Test func captureWarningDestinationsAreDeepLinks() {
    for row in [LayoutRows.widget(.notes, title: "Notes"), LayoutRows.pages] {
        let parsed = SettingsNavigator.parse(row.deepLink)
        #expect(parsed.pane == .nookAndWidgets && parsed.row == row.id)
    }
    #expect(LayoutRows.widget(.notes, title: "Notes").deepLink == SettingsPageID("nook#widget.\(WidgetID.notes.rawValue)"))
    #expect(GeneralRows.excludedApps.deepLink.rawValue.hasPrefix("general#"))
}

// MARK: - Layout & Widgets opened at a widget's library entry

/// The page shown for a widget: the current page when it holds the widget or has room, else the first page that
/// holds it, else the first with room for its minimum; nil when it is on no page and nothing has room.
@Test func layoutShowsAPageThatHoldsOrFitsTheWidget() {
    let sizes: [WidgetID: WidgetSizes] = [.media: WidgetSizes(minimum: 4, preferred: 5, maximum: 6),
                                          .calendar: WidgetSizes(minimum: 2, preferred: 3, maximum: 5),
                                          .quickApps: WidgetSizes(minimum: 1, preferred: 2, maximum: 6),
                                          .notes: WidgetSizes(minimum: 3, preferred: 4, maximum: 8),
                                          .timer: WidgetSizes(minimum: 2, preferred: 2, maximum: 3)]
    let a = NookPage(id: "page.a", symbol: "sparkles", items: [NookItem(.media, cells: 6), NookItem(.calendar, cells: 5)])   // 1 left
    let b = NookPage(id: "page.b", symbol: "sparkles", items: [NookItem(.timer, cells: 2)])                                   // 10 left
    let c = NookPage(id: "page.c", symbol: "sparkles", items: [NookItem(.notes, cells: 4)])
    var editor = LayoutEditor(pages: [NookPreset.listener.page, a, b], maxColumns: 12, sizes: sizes)
    #expect(editor.page(for: .notes, preferring: .nook) == b.id)                         // Home has 2 left: the first with room
    #expect(editor.page(for: .notes, preferring: b.id) == b.id)
    #expect(editor.page(for: .timer, preferring: .nook) == b.id)                         // held by b: room on Home does not count
    #expect(editor.page(for: .todos, preferring: .nook) == .nook)                        // on no page (1–8 cells): Home has room, stay
    #expect(editor.page(for: .todos, preferring: a.id) == a.id)
    #expect(editor.page(for: .media, preferring: b.id) == .nook)                         // on Home and a: the first that holds it
    #expect(editor.page(for: .media, preferring: a.id) == a.id)
    #expect(editor.hasRoom(for: .notes))

    editor = LayoutEditor(pages: [NookPreset.listener.page, a], maxColumns: 12, sizes: sizes)
    #expect(editor.page(for: .notes, preferring: .nook) == nil && !editor.hasRoom(for: .notes))
    editor = LayoutEditor(pages: [NookPreset.listener.page, a, c], maxColumns: 12, sizes: sizes)
    #expect(editor.page(for: .notes, preferring: .nook) == c.id)                         // held even though it is full
}

/// Only a widget's library entry asks for a page: "nook.widget.<id>" (ids may contain dots).
@Test func widgetRowsNameTheirWidget() {
    #expect(LayoutRows.widgetID(inRow: LayoutRows.widget(.notes, title: "Notes").id) == .notes)
    #expect(LayoutRows.widgetID(inRow: "nook.widget.media.player") == .media)
    #expect(LayoutRows.widgetID(inRow: LayoutRows.pages.id) == nil)
    #expect(LayoutRows.widgetID(inRow: "nook.widget.") == nil)
    #expect(LayoutRows.widgetID(inRow: "general.widget.notes.editor") == nil)
}
