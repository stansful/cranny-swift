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

/// Chooses the layout for the width and owns keyboard navigation.
private struct CalendarAgendaLayout: View {
    @Environment(\.cranny) private var theme
    @FocusState private var focused: Bool
    @State private var selection: String?
    let model: CalendarModel
    let context: WidgetContext

    var body: some View {
        let redacted = context.redactsPersonalData || model.isRedacted
        let showsPast = model.settings[CalendarSettings.showsPastEventsToday]
        let now = model.scheduler.now
        let calendar = model.store.clock.calendar()
        let events = model.store.events
        let offset = model.selectedOffset
        let tomorrowFirst = Agenda.firstTimedEvent(in: events, day: EventWindow.day(offset: 1, from: now, calendar: calendar))
        let agenda = { (dayOffset: Int) in
            Agenda.make(events: events, day: EventWindow.day(offset: dayOffset, from: now, calendar: calendar), now: now,
                        isToday: dayOffset == 0, showsPastToday: showsPast)
        }
        let primary = agenda(offset)
        Group {
            if context.cells <= 2 {
                MiniAgenda(agenda: agenda(0), model: model, redacted: redacted)
            } else if context.cells >= 5, offset < model.dayRange.upperBound {
                HStack(alignment: .top, spacing: Space.m) {
                    DayAgenda(agenda: primary, model: model, redacted: redacted, tomorrowFirst: tomorrowFirst,
                              selection: selection, isKeyboardFocused: focused) { EmptyView() }
                    Rectangle().fill(theme.palette.hairline).frame(width: 1).padding(.vertical, Space.xxs)
                    DayAgenda(agenda: agenda(offset + 1), model: model, redacted: redacted, tomorrowFirst: nil,
                              selection: selection, isKeyboardFocused: focused) { DayPager(model: model) }
                }
            } else {
                DayAgenda(agenda: primary, model: model, redacted: redacted, tomorrowFirst: tomorrowFirst,
                          selection: selection, isKeyboardFocused: focused) {
                    if context.cells >= 4 { DayStrip(model: model, today: now) } else { DayPager(model: model) }
                }
            }
        }
        .focusable(context.cells > 2)
        .focused($focused)
        .focusEffectDisabled()
        .onKeyPress(.upArrow) { move(-1, in: primary) }
        .onKeyPress(.downArrow) { move(1, in: primary) }
        .onKeyPress(.leftArrow) { changeDay(-1) }
        .onKeyPress(.rightArrow) { changeDay(1) }
        .onKeyPress(.return) { openSelection(in: primary) }
        .onKeyPress(characters: CharacterSet(charactersIn: "jJ")) { press in
            guard press.modifiers.contains(.command) else { return .ignored }
            return joinSelection(in: primary)
        }
        .onChange(of: focused) { _, isFocused in
            if isFocused, selection == nil { selection = primary.featuredID ?? primary.rows.first?.id }
        }
        // The shell focuses the widget (Tab, or opening from a meeting activity): take keyboard focus with it.
        .onAppear { if context.isFocused && context.cells > 2 { focused = true } }
        .onChange(of: context.isFocused) { _, isFocused in if context.cells > 2 { focused = isFocused } }
        .onChange(of: offset) { _, _ in selection = nil }
    }

    // MARK: Keyboard

    private func move(_ step: Int, in agenda: Agenda) -> KeyPress.Result {
        let ids = agenda.rows.map(\.id)
        guard !ids.isEmpty else { return .ignored }
        let index = selection.flatMap(ids.firstIndex(of:)) ?? (step > 0 ? -1 : ids.count)
        selection = ids[min(max(index + step, 0), ids.count - 1)]
        return .handled
    }

    private func changeDay(_ step: Int) -> KeyPress.Result {
        let target = model.selectedOffset + step
        guard model.dayRange.contains(target) else { return .ignored }
        withAnimation(theme.animation(.tab)) { model.selectDay(target) }
        return .handled
    }

    private func openSelection(in agenda: Agenda) -> KeyPress.Result {
        guard let row = agenda.rows.first(where: { $0.id == selection }) ?? agenda.featured else { return .ignored }
        model.openInCalendar(row.event)
        return .handled
    }

    private func joinSelection(in agenda: Agenda) -> KeyPress.Result {
        let row = agenda.rows.first(where: { $0.id == selection && model.link(for: $0.event) != nil }) ?? agenda.featured
        guard let event = row?.event, model.link(for: event) != nil else { return .ignored }
        model.join(event)
        return .handled
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
