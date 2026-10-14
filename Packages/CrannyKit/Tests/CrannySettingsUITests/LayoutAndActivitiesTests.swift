import CrannyCore
import Foundation
import Testing
@testable import CrannySettingsUI

private let sizes: [WidgetID: WidgetSizes] = [
    .media: WidgetSizes(minimum: 4, preferred: 5, maximum: 6),
    .calendar: WidgetSizes(minimum: 2, preferred: 3, maximum: 5),
    .quickApps: WidgetSizes(minimum: 1, preferred: 2, maximum: 6),
    .timer: WidgetSizes(minimum: 2, preferred: 2, maximum: 3),
    .notes: WidgetSizes(minimum: 3, preferred: 4, maximum: 8),
]

private func editor(maxColumns: Int = 12) -> LayoutEditor {
    LayoutEditor(pages: [NookPreset.listener.page], maxColumns: maxColumns, sizes: sizes)   // media 5 · calendar 3 · apps 2
}

// MARK: - Layout & Widgets (DESIGN.md §6.3, §6.6)

@Test func addingUsesThePreferredWidthOrSqueezesOrRefuses() {
    var e = editor()
    #expect(e.usedCells(on: .nook) == 10 && e.cellsLeft(on: .nook) == 2)
    #expect(e.add(.timer, to: .nook) == nil)                                  // preferred 2 fits exactly
    #expect(e.cells(of: .timer, on: .nook) == 2 && e.cellsLeft(on: .nook) == 0)
    #expect(e.add(.notes, to: .nook) == .overflow(cells: 3))                  // needs at least 3
    #expect(e.add(.timer, to: .nook) == nil && e.page(.nook)?.items.count == 4)   // already there: no duplicate

    var squeeze = editor(maxColumns: 13)
    #expect(squeeze.add(.notes, to: .nook) == nil)
    #expect(squeeze.cells(of: .notes, on: .nook) == 3)                         // minimum, not preferred
}

@Test func resizingClampsToTheWidgetAndRefusesOverflow() {
    var e = editor()
    #expect(e.resize(.media, on: .nook, to: 9) == nil)                        // clamped to the maximum 6
    #expect(e.cells(of: .media, on: .nook) == 6 && e.cellsLeft(on: .nook) == 1)
    #expect(e.resize(.calendar, on: .nook, to: 5) == .overflow(cells: 1))
    #expect(e.cells(of: .calendar, on: .nook) == 3)                            // unchanged
    #expect(e.resize(.calendar, on: .nook, to: 0) == nil)                     // clamped to the minimum 2
    #expect(e.cells(of: .calendar, on: .nook) == 2)
}

@Test func widgetsMoveAndAreRemoved() {
    var e = editor()
    e.shift(.quickApps, on: .nook, by: -1)
    #expect(e.page(.nook)?.items.map(\.widget) == [.media, .quickApps, .calendar])
    e.move(.media, on: .nook, to: 99)
    #expect(e.page(.nook)?.items.map(\.widget) == [.quickApps, .calendar, .media])
    e.shift(.quickApps, on: .nook, by: -1)                                      // already first
    #expect(e.page(.nook)?.items.first?.widget == .quickApps)
    e.remove(.calendar, from: .nook)
    #expect(e.page(.nook)?.items.map(\.widget) == [.quickApps, .media])
}

@Test func usersGetUpToThreePagesAndHomeStays() throws {
    var e = editor()
    for n in 1...3 {
        guard case .success = e.addPage(title: "Page \(n)", symbol: "sparkles", id: PageID("page.\(n)")) else {
            Issue.record("page \(n) refused"); return
        }
    }
    #expect(!e.canAddPage && e.userPageCount == 3)
    #expect(e.addPage(title: "Four", symbol: "sparkles") == .failure(.pageLimit))
    e.rename("page.1", to: "  Focus ")
    #expect(e.page("page.1")?.title == "Focus")
    e.rename("page.1", to: "", symbol: "note.text")
    #expect(e.page("page.1")?.title == "Focus" && e.page("page.1")?.symbol == "note.text")   // a user page keeps a name
    e.rename(.nook, to: "Start")
    #expect(e.page(.nook)?.title == "Start")
    e.rename(.nook, to: " ")
    #expect(e.page(.nook)?.title == nil)                                       // back to the localized "Home"
    e.movePage("page.2", by: -1)
    #expect(e.pages.map(\.id) == [.nook, "page.2", "page.1", "page.3"])
    e.movePage(.nook, by: -1)
    #expect(e.pages.first?.id == .nook)
    e.removePage(.nook)
    e.removePage("page.3")
    #expect(e.pages.map(\.id) == [.nook, "page.2", "page.1"])
    #expect(e.canAddPage)
}

@Test func unknownWidgetsGetTheDesignsSizes() {
    let registry = ModuleRegistry(services: .preview())
    let media = KnownWidgets.info(.media, registry: registry)
    #expect(media.sizes == WidgetSizes(minimum: 4, preferred: 5, maximum: 6) && !media.isRegistered && !media.hasOptions)
    let other = KnownWidgets.info("module.thing", registry: registry)
    #expect(other.title == "module.thing" && other.symbol == "app.dashed")
}

// MARK: - Live Activities (DESIGN.md §9.4)

private func kind(_ id: ActivityID, _ priority: ActivityPriority, enabled: Bool = true, peeks: Bool = false) -> ActivityKind {
    ActivityKind(id: id, module: .system, title: id.rawValue, symbol: "timer", defaultPriority: priority,
                 isEnabledByDefault: enabled, canPeekOnChange: true, peeksOnChangeByDefault: peeks)
}

private let kinds = [kind(.nowPlaying, .ongoing), kind(.hud, .hud), kind(.timerRunning, .ongoing), kind(.meetingSoon, .alert),
                     kind(.meetingNow, .ongoing), kind(.flash, .alert)]

@Test func theHUDIsNotListedAndClassesKeepPriorityOrder() {
    let groups = ActivityOrdering.groups(kinds, order: [])
    #expect(groups.map(\.priority) == [.alert, .ongoing])
    #expect(groups[0].kinds.map(\.id) == [.meetingSoon, .flash])
    #expect(groups[1].kinds.map(\.id) == [.nowPlaying, .timerRunning, .meetingNow])
}

@Test func theUsersOrderBreaksTiesWithinAClassOnly() {
    let groups = ActivityOrdering.groups(kinds, order: [.timerRunning, .flash, .meetingNow])
    #expect(groups[0].kinds.map(\.id) == [.flash, .meetingSoon])
    #expect(groups[1].kinds.map(\.id) == [.timerRunning, .meetingNow, .nowPlaying])
}

@Test func movingWritesATotalOrder() {
    let groups = ActivityOrdering.groups(kinds, order: [])
    let order = ActivityOrdering.moving(in: groups, priority: .ongoing, from: IndexSet(integer: 2), to: 0)
    #expect(order == [.meetingSoon, .flash, .meetingNow, .nowPlaying, .timerRunning])
    #expect(ActivityOrdering.shifting(.timerRunning, by: -1, in: groups) == [.meetingSoon, .flash, .timerRunning, .nowPlaying, .meetingNow])
    #expect(ActivityOrdering.shifting(.meetingNow, by: 1, in: groups) == [.meetingSoon, .flash, .nowPlaying, .timerRunning, .meetingNow])
    #expect(ActivityOrdering.shifting(.flash, by: 1, in: groups) == [.meetingSoon, .flash, .nowPlaying, .timerRunning, .meetingNow])
}

@Test func preferencesStoreOnlyChangesFromTheDefaults() {
    let timer = kind(.timerRunning, .ongoing, enabled: true, peeks: true)
    #expect(ActivityOrdering.preference(timer, in: [:]) == ActivityPreference(isEnabled: true, peeksOnChange: true))
    let off = ActivityOrdering.setting(ActivityPreference(isEnabled: false, peeksOnChange: true), for: timer, in: [:])
    #expect(off[.timerRunning]?.isEnabled == false)
    let back = ActivityOrdering.setting(ActivityPreference(isEnabled: true, peeksOnChange: true), for: timer, in: off)
    #expect(back.isEmpty)
}
