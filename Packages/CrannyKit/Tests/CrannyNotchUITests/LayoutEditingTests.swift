// The layout editor's rules (DESIGN.md §6.3, §6.6): whole cells, the widget's sizes, the page's maximum
// columns, reorder targets — and that every change goes through `commitLayout`, never into settings directly.
import CrannyCore
import Foundation
import Testing
@testable import CrannyNotchUI

private let home = NookPage(id: .nook, symbol: "square.grid.2x2.fill",
                            items: [NookItem(.media, cells: 5), NookItem(.calendar, cells: 3), NookItem(.quickApps, cells: 2)])
private let focus = NookPage(id: "page.focus", title: "Focus", symbol: "note.text", items: [NookItem(.notes, cells: 4)])
private let editing = LayoutEditing(pages: [home, focus], pageID: .nook, maxColumns: 12)
private let media = WidgetSizes(minimum: 4, preferred: 5, maximum: 6)
private let calendar = WidgetSizes(minimum: 2, preferred: 3, maximum: 5)

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
        #expect(try #require(editing.resizing(at: 0, to: 6, sizes: media)).items[0].cells == 6)
        #expect(try #require(editing.resizing(at: 0, to: 9, sizes: media)).items[0].cells == 6)   // widget maximum
        #expect(try #require(editing.resizing(at: 1, to: 5, sizes: calendar)).items[1].cells == 5)  // 12 used: the room
        let full = try #require(editing.resizing(at: 1, to: 5, sizes: calendar))
        #expect(full.cellsLeft == 0)
        #expect(full.resizing(at: 0, to: 6, sizes: media) == nil)                 // no room left: refused
        #expect(try #require(editing.resizing(at: 0, to: 1, sizes: media)).items[0].cells == 4)   // widget minimum
        #expect(editing.resizing(at: 0, to: 5, sizes: media) == nil)              // no change
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
    }
}
