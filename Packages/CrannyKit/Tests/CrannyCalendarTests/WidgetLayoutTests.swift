import CrannyCore
import Foundation
import Testing
@testable import CrannyCalendar

/// What the widget shows at each width and what the keyboard can reach (DESIGN.md §6.7, §7.2, §16): 2 cells are
/// focusable with their two rows; 5 cells show two clamped columns; ⌘J prefers the meeting in progress, then the
/// one starting soon.
@Suite @MainActor struct WidgetLayoutTests {
    private let time = TestTime(T.date(h: 10))
    private let workshop = T.event("workshop", start: T.date(h: 9, 30), minutes: 60, title: "Workshop")
    private let call = T.event("call", start: T.date(h: 10, 4), minutes: 15, title: "Call", link: "https://zoom.us/j/7")
    private let lunch = T.event("lunch", start: T.date(h: 12), minutes: 60, title: "Lunch")
    private let tomorrow = T.event("tomorrow", start: T.date(2026, 10, 15, h: 9), title: "Planning")

    @Test func twoCellsReachTheirTwoRows() async {
        let model = await makeModel([workshop, call, lunch, tomorrow], time: time)
        let layout = AgendaColumns(model: model, cells: 2)
        #expect(layout.isMini)
        #expect(layout.selectableRows(0).map(\.id) == ["workshop", "call"])           // the rows MiniAgenda draws
        #expect(layout.entryRow(column: 0) == "workshop")
        #expect(layout.row(column: 0, id: "call")?.event.title == "Call")
    }

    @Test func twoCellsEmptyDayKnowsTomorrow() async {
        time.now = T.date(h: 18)
        let model = await makeModel([workshop, tomorrow], time: time)
        let layout = AgendaColumns(model: model, cells: 2)
        #expect(layout.selectableRows(0).isEmpty)
        #expect(layout.tomorrowFirst?.id == "tomorrow")
    }

    @Test func joinPrefersTheLiveMeetingThenTheSoonOne() async {
        // The workshop (no link) runs; the call starts in 4 minutes: both are featured, live first, and only the
        // call can be joined — what ⌘J and the activity's click-through land on.
        let model = await makeModel([workshop, call, lunch], time: time)
        #expect(model.scheduler.state.soon?.event.id == "call")
        let layout = AgendaColumns(model: model, cells: 3)
        #expect(layout.featured.map(\.id) == ["workshop", "call"])
        #expect(layout.featured.first { model.link(for: $0.event) != nil }?.id == "call")
        #expect(layout.entryRow(column: 0) == "workshop")
    }

    @Test func fiveCellsShowTwoColumnsInsideTheWindow() async {
        let services = CrannyServices.preview()
        let model = await makeModel([workshop, tomorrow], time: time, services: services)
        // Defaults: today and tomorrow — both shown, nowhere to page.
        var layout = AgendaColumns(model: model, cells: 5)
        #expect(layout.columns.count == 2)
        #expect(layout.columns.map(\.isToday) == [true, false])
        #expect(!model.canPage(-1, columns: 2) && !model.canPage(1, columns: 2))
        #expect(model.canPage(1, columns: 1))                                         // 3 cells: › to tomorrow

        // At 3 cells the user paged to tomorrow; widened to 5 the pair stays (today, tomorrow) instead of turning
        // into the single-column layout.
        model.page(1)
        #expect(model.selectedOffset == 1)
        layout = AgendaColumns(model: model, cells: 5)
        #expect(layout.firstOffset == 0 && layout.columns.count == 2)

        // A wider window pages both columns together and stops with the last day in the second column.
        services.settings[CalendarSettings.daysAhead] = 3
        model.page(1, columns: 2)
        model.page(1, columns: 2)
        #expect(model.firstShownOffset(columns: 2) == 2)
        #expect(!model.canPage(1, columns: 2))
        model.page(1, columns: 2)                                                     // ignored
        #expect(model.firstShownOffset(columns: 2) == 2)
        #expect(AgendaColumns(model: model, cells: 5).columns.map(\.isToday) == [false, false])

        // A one-day window never shows a column outside it.
        services.settings[CalendarSettings.daysAhead] = 0
        #expect(AgendaColumns(model: model, cells: 5).columns.count == 1)
    }

    @Test func selectionLandsOnTheFeaturedRowOfAColumn() async {
        let model = await makeModel([workshop, call, lunch, tomorrow], time: time)
        let layout = AgendaColumns(model: model, cells: 5)
        #expect(layout.entryRow(column: 0) == "workshop")
        #expect(layout.entryRow(column: 1) == "tomorrow")                             // no featured row: the first
        #expect(layout.entryRow(column: 2) == nil)
    }
}
