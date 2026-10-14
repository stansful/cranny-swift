// The layout editor's rules (DESIGN.md §6.3, §6.6): whole cells, the widget's sizes, the page's maximum
// columns, reorder targets — and that every change goes through `commitLayout`, never into settings directly.
import CrannyCore
import Foundation
import Testing
@testable import CrannyNotchUI

private let home = NookPage(id: .nook, symbol: "square.grid.2x2.fill",
                            items: [NookItem(.media, cells: 5), NookItem(.calendar, cells: 3), NookItem(.quickApps, cells: 2)])
private let focus = NookPage(id: "page.focus", title: "Focus", symbol: "note.text", items: [NookItem(.notes, cells: 4)])
private let media = WidgetSizes(minimum: 4, preferred: 5, maximum: 6)
private let calendar = WidgetSizes(minimum: 2, preferred: 3, maximum: 5)
private let editing = LayoutEditing(pages: [home, focus], pageID: .nook, maxColumns: 12,
                                    sizes: [.media: media, .calendar: calendar])

@Suite("Layout editing (DESIGN.md §6.6)") struct LayoutEditingTests {
    @Test func countsCellsLeft() {
        #expect(editing.usedColumns == 10 && editing.cellsLeft == 2)
    }

    @Test func movesWithinThePageOnly() throws {
        let moved = try #require(editing.moving(from: 0, to: 2))
        #expect(moved.items.map(\.widget) == [.calendar, .quickApps, .media])
        #expect(moved.pages[1] == focus)                                          // other pages untouched
        #expect(editing.moving(from: 0, to: -3)?.items.first?.widget == nil)      // clamped to 0 = no change
        #expect(editing.moving(from: 2, to: 9)?.items == nil)                     // already last
        #expect(editing.moving(from: 7, to: 0) == nil)
    }

    @Test func resizesInWholeCellsWithinSizesAndRoom() throws {
        #expect(try #require(editing.resizing(at: 0, to: 6)).items[0].cells == 6)
        #expect(try #require(editing.resizing(at: 0, to: 9)).items[0].cells == 6)   // widget maximum
        #expect(try #require(editing.resizing(at: 1, to: 5)).items[1].cells == 5)  // 12 used: the room
        let full = try #require(editing.resizing(at: 1, to: 5))
        #expect(full.cellsLeft == 0)
        #expect(full.resizing(at: 0, to: 6) == nil)                 // no room left: refused
        #expect(try #require(editing.resizing(at: 0, to: 1)).items[0].cells == 4)   // widget minimum
        #expect(editing.resizing(at: 0, to: 5) == nil)              // no change
    }

    /// A stored width outside the widget's sizes (old settings, a module that changed its sizes) counts as it is
    /// drawn: clamped. Before, "N cells left", the Add menu's overflow and the ⋯ Resize choices used the stored
    /// width and disagreed with the grid and the owner's `openColumns`.
    @Test func countsWidthsAsDrawn() throws {
        let stale = NookPage(id: .nook, symbol: "square.grid.2x2.fill",
                             items: [NookItem(.media, cells: 9), NookItem(.calendar, cells: 1), NookItem(.quickApps, cells: 2)])
        let e = LayoutEditing(pages: [stale], pageID: .nook, maxColumns: 12, sizes: [.media: media, .calendar: calendar])
        #expect(e.cells(of: stale.items[0]) == 6 && e.cells(of: stale.items[1]) == 2)
        #expect(e.usedColumns == 10 && e.cellsLeft == 2)                          // 6 + 2 + 2, not 9 + 1 + 2
        #expect(e.allowedSizes(for: .calendar) == [2, 3, 4])                        // 2 drawn + 2 left
        #expect(e.allowedSizes(for: .media) == [4, 5, 6])
        #expect(e.allowedSizes(for: .quickApps) == [])                              // no sizes: no choices
        #expect(e.resizing(at: 0, to: 6) == nil)                                    // already drawn at 6
        #expect(try #require(e.resizing(at: 1, to: 4)).items[1].cells == 4)        // others count 6 + 2
        #expect(e.overflow(adding: WidgetSizes(minimum: 3, preferred: 3, maximum: 3)) == 1)
    }

    @Test func addsAtThePreferredWidthOrRefuses() throws {
        let timer = WidgetSizes(minimum: 2, preferred: 2, maximum: 3)
        let added = try #require(editing.adding(.timer, sizes: timer))
        #expect(added.items.last == NookItem(.timer, cells: 2) && added.cellsLeft == 0)
        #expect(editing.overflow(adding: timer) == 0)
        let notes = WidgetSizes(minimum: 3, preferred: 4, maximum: 8)
        #expect(editing.adding(.notes, sizes: notes) == nil)                      // 1 cell over
        #expect(editing.overflow(adding: notes) == 1)
        #expect(editing.adding(.media, sizes: media) == nil)                      // already on the page
        let roomy = LayoutEditing(pages: [focus], pageID: "page.focus", maxColumns: 12)
        #expect(roomy.adding(.media, sizes: media)?.items.last == NookItem(.media, cells: 5))
    }

    @Test func removes() throws {
        let removed = try #require(editing.removing(.calendar))
        #expect(removed.items.map(\.widget) == [.media, .quickApps] && removed.cellsLeft == 5)
        #expect(editing.removing(.timer) == nil)
    }

    @Test func dropTargetFollowsTheDraggedCardsCentre() {
        let widths: [CGFloat] = [312, 184, 120]                                   // 5, 3, 2 cells at Standard
        #expect(LayoutEditing.dropIndex(widths: widths, gutter: 8, from: 0, translation: 50) == 0)
        #expect(LayoutEditing.dropIndex(widths: widths, gutter: 8, from: 0, translation: 260) == 1)
        #expect(LayoutEditing.dropIndex(widths: widths, gutter: 8, from: 0, translation: 500) == 2)
        #expect(LayoutEditing.dropIndex(widths: widths, gutter: 8, from: 2, translation: -100) == 2)   // not past Calendar's centre
        #expect(LayoutEditing.dropIndex(widths: widths, gutter: 8, from: 2, translation: -200) == 1)
        #expect(LayoutEditing.dropIndex(widths: widths, gutter: 8, from: 2, translation: -600) == 0)
        #expect(LayoutEditing.dropIndex(widths: widths, gutter: 8, from: 1, translation: 0) == 1)
    }

    @Test func resizeHandleStepsWholeCells() {
        #expect(LayoutEditing.cellDelta(translation: 30, cell: 56, gutter: 8) == 0)
        #expect(LayoutEditing.cellDelta(translation: 33, cell: 56, gutter: 8) == 1)
        #expect(LayoutEditing.cellDelta(translation: -130, cell: 56, gutter: 8) == -2)
    }

    /// DESIGN.md §6.8: the ⋯ menu (Options, Resize, Remove, Edit Layout…) is also a VoiceOver action; Resize is
    /// "Wider" / "Narrower", one allowed width at a time.
    @Test func voiceOverResizeStepsThroughAllowedWidths() {
        #expect(CardAccessibilityActions.resizeSteps(cells: 3, allowed: [2, 3, 4, 5]) == (4, 2))
        #expect(CardAccessibilityActions.resizeSteps(cells: 5, allowed: [4, 5]) == (nil, 4))
        #expect(CardAccessibilityActions.resizeSteps(cells: 2, allowed: [2]) == (nil, nil))      // nothing to offer
        #expect(CardAccessibilityActions.resizeSteps(cells: 4, allowed: []) == (nil, nil))       // unregistered widget
    }

    /// DESIGN.md §16: opening puts VoiceOver on the first widget, or on the widget the panel opened for.
    @Test func voiceOverLandsOnTheFocusedOrFirstWidgetWhenOpening() {
        let items = home.items
        #expect(WidgetGridPage.voiceOverTarget(entrance: true, focus: nil, items: items) == .media)
        #expect(WidgetGridPage.voiceOverTarget(entrance: true, focus: .calendar, items: items) == .calendar)
        #expect(WidgetGridPage.voiceOverTarget(entrance: true, focus: .timer, items: items) == .media)   // not on the page
        #expect(WidgetGridPage.voiceOverTarget(entrance: false, focus: .calendar, items: items) == nil)  // tab switch
        #expect(WidgetGridPage.voiceOverTarget(entrance: true, focus: nil, items: []) == nil)
    }

    @Test func everyLayoutChangeHasAnAnnouncement() {
        #expect(LayoutAnnouncement.added("Timer").contains("Timer"))
        #expect(LayoutAnnouncement.removed("Timer").contains("Timer"))
        #expect(LayoutAnnouncement.resized("Timer", cells: 3).contains("3"))
        #expect(LayoutAnnouncement.moved("Timer", position: 2).contains("2"))
    }

    @MainActor @Test func cardMenuWritesThroughCommitLayout() {
        let services = CrannyServices.preview()
        services.settings[CoreSettings.pages] = [home]
        let registry = ModuleRegistry(services: services)
        let model = NotchSceneModel(layout: NotchLayout(metrics: .reference), theme: CrannyTheme())
        var committed: [[NookPage]] = []
        var modes: [NookMode] = []
        var actions = NotchUIActions()
        actions.commitLayout = { committed.append($0) }
        actions.setMode = { modes.append($0) }
        let commands = GridCommands.make(page: home, model: model, registry: registry, actions: actions)
        commands.remove(.quickApps)
        commands.editLayout()
        #expect(committed.last?.first?.items.map(\.widget) == [.media, .calendar])
        #expect(modes == [.editLayout])
        #expect(services.settings[CoreSettings.pages] == [home])                 // NotchUI never writes settings
        #expect(commands.allowedSizes(.media) == [])                              // unregistered widget: no sizes
        registry.add(widget: ProbeWidget(.calendar, sizes: calendar, probe: NotchLifecycleProbe()))
        #expect(commands.allowedSizes(.calendar) == [2, 3, 4, 5])                 // 3 drawn + 2 left, max 5
    }
}

/// The panel's layout editor and Settings ▸ Layout & Widgets show on one screen, so their Russian copy says the
/// same things the same way (DESIGN.md §17); the width actions are verb phrases, because a bare «Уже» reads and is
/// spoken as уже́, "already".
@Suite("Layout editor copy in Russian (DESIGN.md §17)") struct LayoutEditorCopyTests {
    private let russian = Locale(identifier: "ru")

    private func catalog() throws -> Bundle {
        let path = try #require(Bundle.module.path(forResource: "ru", ofType: "lproj"))
        return try #require(Bundle(path: path))
    }

    @Test func actionsAreVerbPhrases() throws {
        let ru = try catalog()
        func text(_ key: String) -> String { ru.localizedString(forKey: key, value: nil, table: "Localizable") }
        #expect(text("Narrower") == "Уменьшить ширину")
        #expect(text("Wider") == "Увеличить ширину")
        #expect(text("Move left") == "Переместить влево")
        #expect(text("Move right") == "Переместить вправо")
    }

    @Test func cellCountsUseTheWordsOfTheSettingsEditor() throws {
        let ru = try catalog()
        let left = ru.localizedString(forKey: "%lld cells left", value: nil, table: "Localizable")
        #expect(String(format: left, locale: russian, 1) == "Свободна 1 ячейка")
        #expect(String(format: left, locale: russian, 3) == "Свободно 3 ячейки")
        #expect(String(format: left, locale: russian, 5) == "Свободно 5 ячеек")
        let over = ru.localizedString(forKey: "%@ — %lld cells over; move a widget to another page", value: nil,
                                      table: "Localizable")
        #expect(String(format: over, locale: russian, "Погода", 1)
                == "Погода — не помещается 1 ячейка; перенесите виджет на другую страницу")
        #expect(String(format: over, locale: russian, "Погода", 2)
                == "Погода — не помещаются 2 ячейки; перенесите виджет на другую страницу")
        #expect(String(format: over, locale: russian, "Погода", 5)
                == "Погода — не помещаются 5 ячеек; перенесите виджет на другую страницу")
    }
}
