// CrannyCalendar/UI/Widget/DayAgenda.swift — the widget's layouts by width (DESIGN.md §6.7): 2 cells — weekday,
// date and the next two events (times only); 3 — header with ‹ › and the day's list with Join; 4 — the day strip
// instead of ‹ ›; 5 — two columns, the shown day and the next. Keyboard (§7.2): ↑ ↓ events, ↩ open in Calendar,
// ⌘J join, ← → change day.
import CrannyCore
import Foundation
import SwiftUI

/// One day: header + list (3 and 4 cells, and each column of 5).
struct DayAgenda<Trailing: View>: View {
    let agenda: Agenda
    let model: CalendarModel
    let redacted: Bool
    let tomorrowFirst: EventSnapshot?
    let selection: String?
    let isKeyboardFocused: Bool
    private let trailing: Trailing

    init(agenda: Agenda, model: CalendarModel, redacted: Bool, tomorrowFirst: EventSnapshot?, selection: String?,
         isKeyboardFocused: Bool, @ViewBuilder trailing: () -> Trailing) {
        self.agenda = agenda; self.model = model; self.redacted = redacted; self.tomorrowFirst = tomorrowFirst
        self.selection = selection; self.isKeyboardFocused = isKeyboardFocused; self.trailing = trailing()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            DayHeader(date: agenda.day.start, isToday: agenda.isToday) { trailing }
            if agenda.isEmptyToday || agenda.isEmpty {
                EmptyDayState(isToday: agenda.isToday, tomorrowFirst: tomorrowFirst, redacted: redacted)
            } else {
                AgendaList(agenda: agenda, model: model, redacted: redacted, selection: selection, isKeyboardFocused: isKeyboardFocused)
            }
        }
    }
}

/// 2 cells: "TUE / 14" and the next two events of today (start times only, no Join).
struct MiniAgenda: View {
    @Environment(\.cranny) private var theme
    let agenda: Agenda
    let model: CalendarModel
    let redacted: Bool

    var body: some View {
        let p = theme.palette
        let upcoming = agenda.rows.filter { $0.role == .live || $0.role == .next || $0.role == .upcoming }.prefix(2)
        VStack(alignment: .leading, spacing: 0) {
            Text(CalendarFormat.weekday(agenda.day.start))
                .crannyFont(.micro)
                .foregroundStyle(agenda.isToday ? p.danger : p.secondaryLabel)
            Text(CalendarFormat.dayNumber(agenda.day.start))
                .crannyFont(.numeral)
                .foregroundStyle(p.label)
            Spacer(minLength: Space.xs)
            if upcoming.isEmpty {
                Text("No more events today", bundle: .module, comment: "Calendar widget: empty state for the rest of today")
                    .crannyFont(.caption)
                    .foregroundStyle(p.tertiaryLabel)
                    .lineLimit(2)
            } else {
                VStack(alignment: .leading, spacing: Space.xxs) {
                    ForEach(Array(upcoming)) { row in MiniRow(row: row, model: model, redacted: redacted) }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .contain)
    }
}

private struct MiniRow: View {
    @Environment(\.cranny) private var theme
    let row: Agenda.Row
    let model: CalendarModel
    let redacted: Bool

    var body: some View {
        let p = theme.palette
        let event = row.event
        let live = row.role == .live
        HStack(spacing: Space.xs) {
            CalendarMark(color: event.color, height: 12)
            Text(live ? CalendarFormat.now : row.role == .allDay ? CalendarFormat.allDay : CalendarFormat.bandTime(event.start))
                .crannyFont(.caption)
                .foregroundStyle(live ? theme.eventColor(event.color) : p.secondaryLabel)
                .fixedSize()
            Text(CalendarFormat.title(event, redacted: redacted))
                .crannyFont(.caption)
                .foregroundStyle(p.label)
                .lineLimit(1)
        }
        .frame(height: 16)
        .contentShape(Rectangle())
        .onTapGesture { model.openInCalendar(event) }
        .help(CalendarFormat.subtitle(event, link: model.link(for: event), redacted: redacted))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { model.openInCalendar(event) }
    }
}

#Preview("2 cells") {
    let services = CrannyServices.preview()
    let model = CalendarModel.sample(services: services)
    let now = model.scheduler.now
    let agenda = Agenda.make(events: model.store.events, day: EventWindow.day(offset: 0, from: now, calendar: .autoupdatingCurrent),
                             now: now, isToday: true, showsPastToday: true)
    MiniAgenda(agenda: agenda, model: model, redacted: false)
        .crannyCard(cells: 2)
        .padding()
        .background(.black)
        .crannyThemeRoot(CrannyTheme())
}
