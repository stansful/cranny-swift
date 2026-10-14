// CrannyCalendar/UI/Widget/CalendarWidget.swift — the Calendar widget (DESIGN.md §7.2; 2–5 cells, default 3).
// Content only: CrannyNotchUI draws the card, hover, the ⋯ menu and the VoiceOver container. On a preview stage
// (Settings, onboarding) without calendar access it shows the sample day instead of asking for access.
import CrannyCore
import Foundation
import SwiftUI

@MainActor final class CalendarWidget: NookWidget {
    let id: WidgetID = .calendar
    let symbol = "calendar"
    let sizes = WidgetSizes(minimum: 2, preferred: 3, maximum: 5)
    var title: String { String(localized: "Calendar", bundle: .module, comment: "Calendar: module name (widget, Settings pane, ⌘K result kind)") }
    var summary: String { String(localized: "Today's events, with Join for meetings", bundle: .module, comment: "Widget library: Calendar description") }

    private let model: CalendarModel
    private let services: CrannyServices
    /// The preview stage's sample day, refreshed every 10 minutes so its times stay plausible.
    private var sample: (model: CalendarModel, created: Date)?

    init(model: CalendarModel, services: CrannyServices) {
        self.model = model
        self.services = services
    }

    func makeBody(context: WidgetContext) -> some View {
        CalendarWidgetView(model: displayModel(for: context), context: context)
    }

    func makeOptions() -> some View { CalendarWidgetOptions(settings: services.settings) }

    private func displayModel(for context: WidgetContext) -> CalendarModel {
        guard context.isPreview, model.store.accessStatus != .granted else { return model }
        if let sample, sample.created.timeIntervalSinceNow > -600 { return sample.model }
        let fresh = CalendarModel.sample(services: services)
        sample = (fresh, Date())
        return fresh
    }
}

struct CalendarWidgetView: View {
    @Environment(\.cranny) private var theme
    let model: CalendarModel
    let context: WidgetContext

    var body: some View {
        Group {
            switch model.store.phase {
            case .needsAccess(let status):
                CalendarAccessState(status: status, model: model, context: context)
            case .loading:
                CalendarLoadingState()
            case .failed(let error):
                CalendarErrorState(error: error, model: model)
            case .ready:
                if !model.store.calendars.isEmpty && model.store.visibleCalendarCount == 0 {
                    AllCalendarsHiddenState(total: model.store.calendars.count, model: model)
                } else {
                    CalendarAgendaLayout(model: model, context: context)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .allowsHitTesting(!context.isEditingLayout)                  // nothing fights the layout editor's drag
        .transition(.opacity.animation(theme.animation(.contentSwap)))
        .onDisappear { model.dayOffset = 0 }                        // the Nook opens on today again
    }
}

/// Chooses the layout for the width and owns keyboard navigation (DESIGN.md §7.2, §16): ↑ ↓ events, ↩ or Space
/// open in Calendar, ⌘J join, ← → change day. With two columns (5 cells) ← → first move between the columns,
/// then page; ↑ ↓ work in the column that holds the selection. At 2 cells ↑ ↓ ↩ work on the two rows shown.
private struct CalendarAgendaLayout: View {
    @Environment(\.cranny) private var theme
    @FocusState private var focused: Bool
    /// The keyboard's column (5 cells: 0 or 1) and the selected row in it. A multi-day event appears in both
    /// columns with the same id, so the column is part of the selection.
    @State private var column = 0
    @State private var selection: String?
    let model: CalendarModel
    let context: WidgetContext

    var body: some View {
        let redacted = context.redactsPersonalData || model.isRedacted
        let layout = AgendaColumns(model: model, cells: context.cells)
        let primary = layout.columns[0]
        Group {
            if layout.isMini {
                MiniAgenda(agenda: primary, model: model, redacted: redacted, tomorrowFirst: layout.tomorrowFirst,
                           selection: selected(in: 0), isKeyboardFocused: focused)
            } else if layout.columns.count == 2 {
                HStack(alignment: .top, spacing: Space.m) {
                    DayAgenda(agenda: primary, model: model, redacted: redacted, tomorrowFirst: layout.tomorrowFirst,
                              selection: selected(in: 0), isKeyboardFocused: focused) { EmptyView() }
                    Rectangle().fill(theme.palette.hairline).frame(width: 1).padding(.vertical, Space.xxs)
                    DayAgenda(agenda: layout.columns[1], model: model, redacted: redacted, tomorrowFirst: nil,
                              selection: selected(in: 1), isKeyboardFocused: focused) { DayPager(model: model, columns: 2) }
                }
            } else {
                DayAgenda(agenda: primary, model: model, redacted: redacted, tomorrowFirst: layout.tomorrowFirst,
                          selection: selected(in: 0), isKeyboardFocused: focused) {
                    if context.cells >= 4 { DayStrip(model: model, today: model.scheduler.now) } else { DayPager(model: model) }
                }
            }
        }
        .animation(theme.animation(.tab), value: layout.firstOffset)    // ‹ ›, the strip and ← → change the day alike
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onKeyPress(.upArrow) { move(-1, in: layout) }
        .onKeyPress(.downArrow) { move(1, in: layout) }
        .onKeyPress(.leftArrow) { sideways(-1, in: layout) }
        .onKeyPress(.rightArrow) { sideways(1, in: layout) }
        .onKeyPress(.return) { open(in: layout) }
        .onKeyPress(.space) { open(in: layout) }
        .onKeyPress(characters: CharacterSet(charactersIn: "jJ")) { press in
            guard press.modifiers.contains(.command) else { return .ignored }
            return join(in: layout)
        }
        .onChange(of: focused) { _, isFocused in
            if isFocused, selection == nil { column = 0; selection = layout.entryRow(column: 0) }
        }
        // The shell focuses the widget (Tab, or opening from a meeting activity): take keyboard focus with it.
        .onAppear { if context.isFocused { focused = true } }
        .onChange(of: context.isFocused) { _, isFocused in focused = isFocused }
        // ‹ › or the strip changed the day under the selection: drop it unless the row is still there.
        .onChange(of: layout.firstOffset) { _, _ in
            if column >= layout.columns.count { column = 0 }
            if layout.row(column: column, id: selection) == nil { selection = nil }
        }
    }

    private func selected(in index: Int) -> String? { column == index ? selection : nil }

    // MARK: Keyboard

    private func move(_ step: Int, in layout: AgendaColumns) -> KeyPress.Result {
        let ids = layout.selectableRows(column).map(\.id)
        guard !ids.isEmpty else { return .ignored }
        let index = selection.flatMap(ids.firstIndex(of:)) ?? (step > 0 ? -1 : ids.count)
        selection = ids[min(max(index + step, 0), ids.count - 1)]
        return .handled
    }

    /// ← →: to the other column when there is one in that direction, else page the day(s).
    private func sideways(_ step: Int, in layout: AgendaColumns) -> KeyPress.Result {
        guard !layout.isMini else { return .ignored }
        let target = column + step
        if layout.columns.indices.contains(target) {
            column = target
            selection = layout.entryRow(column: target)
            return .handled
        }
        let count = layout.columns.count
        guard model.canPage(step, columns: count) else { return .ignored }
        model.page(step, columns: count)
        selection = AgendaColumns(model: model, cells: context.cells).entryRow(column: column)
        return .handled
    }

    private func open(in layout: AgendaColumns) -> KeyPress.Result {
        guard let row = layout.row(column: column, id: selection) ?? layout.featured.first else { return .ignored }
        model.openInCalendar(row.event)
        return .handled
    }

    /// The selected row if it has a link, else the featured rows in order (the meeting in progress, then the one
    /// starting soon): the first that can be joined.
    private func join(in layout: AgendaColumns) -> KeyPress.Result {
        let candidates = [layout.row(column: column, id: selection)].compactMap(\.self) + layout.featured
        guard let event = candidates.first(where: { model.link(for: $0.event) != nil })?.event else { return .ignored }
        model.join(event)
        return .handled
    }
}

/// The days the widget shows at its width and the rows the keyboard can reach.
@MainActor struct AgendaColumns {
    let isMini: Bool
    let firstOffset: Int
    let columns: [Agenda]
    let tomorrowFirst: EventSnapshot?

    init(model: CalendarModel, cells: Int) {
        let now = model.scheduler.now
        let calendar = model.store.clock.calendar()
        let events = model.store.events
        let showsPast = model.settings[CalendarSettings.showsPastEventsToday]
        let soonID = model.scheduler.state.soon?.event.id
        func agenda(_ offset: Int) -> Agenda {
            Agenda.make(events: events, day: EventWindow.day(offset: offset, from: now, calendar: calendar), now: now,
                        isToday: offset == 0, showsPastToday: showsPast, soonID: soonID)
        }
        isMini = cells <= 2
        // Two columns need two days in the window; the pair is clamped so the second never leaves it.
        let count = !isMini && cells >= 5 && model.dayRange.count >= 2 ? 2 : 1
        let first = isMini ? 0 : model.firstShownOffset(columns: count)
        firstOffset = first
        columns = (0..<count).map { agenda(first + $0) }
        tomorrowFirst = Agenda.firstTimedEvent(in: events, day: EventWindow.day(offset: 1, from: now, calendar: calendar))
    }

    /// The rows ↑ ↓ move through: the two shown at 2 cells, else the day's list.
    func selectableRows(_ column: Int) -> [Agenda.Row] {
        guard columns.indices.contains(column) else { return [] }
        return isMini ? MiniAgenda.rows(columns[column]) : columns[column].rows
    }

    /// Today's featured rows (live, then soon), wherever today is shown.
    var featured: [Agenda.Row] { columns.first(where: \.isToday)?.featured ?? [] }

    /// Where the selection lands in a column: its first featured row, else its first row.
    func entryRow(column: Int) -> String? {
        let rows = selectableRows(column)
        let featured = columns.indices.contains(column) ? columns[column].featuredIDs : []
        return rows.first(where: { featured.contains($0.id) })?.id ?? rows.first?.id
    }

    func row(column: Int, id: String?) -> Agenda.Row? {
        guard let id else { return nil }
        return selectableRows(column).first { $0.id == id }
    }
}

#Preview("Calendar widget · 2 to 5 cells") {
    let services = CrannyServices.preview()
    let widget = CalendarWidget(model: .sample(services: services), services: services)
    let grid = CrannyTheme().grid
    VStack(alignment: .leading, spacing: Space.m) {
        HStack(alignment: .top, spacing: Space.m) {
            ForEach([2, 3], id: \.self) { cells in
                widget.makeBody(context: WidgetContext(cells: cells, contentSize: CGSize(width: grid.width(cells: cells) - 24, height: 96)))
                    .crannyCard(cells: cells)
            }
        }
        ForEach([4, 5], id: \.self) { cells in
            widget.makeBody(context: WidgetContext(cells: cells, contentSize: CGSize(width: grid.width(cells: cells) - 24, height: 96)))
                .crannyCard(cells: cells)
        }
    }
    .padding()
    .background(.black)
    .crannyThemeRoot(CrannyTheme())
}
