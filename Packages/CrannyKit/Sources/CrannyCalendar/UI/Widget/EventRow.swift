// CrannyCalendar/UI/Widget/EventRow.swift — one event in the widget (DESIGN.md §7.2). Ordinary rows are one
// 18-pt line: calendar capsule · title (`caption`) · start time (`caption`, mono, secondary). The live or next
// event is featured on two lines — title, then "Now · 12m left" / "In 4m" in the event colour — with Join when it
// has a link; while one is live, the meeting "Meeting soon" announces is featured as well. Today's ended events are tertiary and struck through (not dimmed alone, §16).
import CrannyCore
import Foundation
import SwiftUI

/// What a row needs from its list.
struct EventRowContext {
    let model: CalendarModel
    let isToday: Bool
    let redacted: Bool
    let isSelected: Bool
    let isKeyboardFocused: Bool
}

struct EventRow: View {
    @Environment(\.cranny) private var theme
    @State private var hovered = false
    let row: Agenda.Row
    let context: EventRowContext

    var body: some View {
        let p = theme.palette
        let event = row.event
        let ended = row.role == .ended
        HStack(spacing: Space.s) {
            CalendarMark(color: event.color, dimmed: ended)
            Text(CalendarFormat.title(event, redacted: context.redacted))
                .crannyFont(.caption)
                .foregroundStyle(ended ? p.tertiaryLabel : p.label)
                // Today's ended events are struck through; earlier days only under Differentiate Without Color.
                .strikethrough(ended && (context.isToday || theme.differentiateWithoutColor), color: p.tertiaryLabel)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(row.role == .allDay ? CalendarFormat.allDay : CalendarFormat.time(event.start))
                .crannyFont(.caption)
                .foregroundStyle(ended || row.role == .allDay ? p.tertiaryLabel : p.secondaryLabel)
                .lineLimit(1)
                .fixedSize()
        }
        .frame(height: AgendaScroll.rowHeight)
        .rowChrome(hovered: hovered, isSelected: context.isSelected, isKeyboardFocused: context.isKeyboardFocused)
        .onHover { hovered = $0 }
        .eventAccessibility(row: row, context: context)
    }
}

struct FeaturedEventRow: View {
    @Environment(\.cranny) private var theme
    @State private var hovered = false
    let row: Agenda.Row
    let context: EventRowContext

    var body: some View {
        let event = row.event
        let link = context.model.link(for: event)
        // Prefer Join with its word (or the start time) beside a fully readable "Now · 12m left"; when the row is too
        // narrow, Join keeps only its glyph and the start time goes (the second line matters more).
        ViewThatFits(in: .horizontal) {
            content(event: event, link: link, roomy: true)
            content(event: event, link: link, roomy: false)
        }
        .rowChrome(hovered: hovered, isSelected: context.isSelected, isKeyboardFocused: context.isKeyboardFocused)
        .onHover { hovered = $0 }
        .eventAccessibility(row: row, context: context)
    }

    private func content(event: EventSnapshot, link: MeetingLink?, roomy: Bool) -> some View {
        let p = theme.palette
        let live = row.role == .live
        return HStack(spacing: Space.s) {
            CalendarMark(color: event.color, height: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(CalendarFormat.title(event, redacted: context.redacted))
                    .crannyFont(.caption).fontWeight(.semibold)
                    .foregroundStyle(p.label)
                    .lineLimit(1)
                    .frame(minWidth: 0, idealWidth: 64, maxWidth: .infinity, alignment: .leading)
                MinuteClock(anchor: live ? event.end : event.start) { tick in
                    let now = context.model.displayNow(tick)
                    let text = live ? CalendarFormat.nowWithTimeLeft(minutes: max(MinuteMath.minutesUntil(event.end, from: now), 1))
                                    : CalendarFormat.startsIn(minutes: max(MinuteMath.minutesUntil(event.start, from: now), 1))
                    Text(text)
                        .crannyFont(.caption)
                        .foregroundStyle(theme.eventColor(event.color))
                        .lineLimit(1)
                        .contentTransition(.numericText(countsDown: true))
                        .animation(theme.animation(.contentSwap), value: text)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if link != nil {
                JoinButton(size: .row(word: roomy)) { context.model.join(event) }
            } else if roomy {
                Text(CalendarFormat.time(event.start))
                    .crannyFont(.caption)
                    .foregroundStyle(p.secondaryLabel)
                    .fixedSize()
            }
        }
        .frame(height: AgendaScroll.featuredHeight)
    }
}

// MARK: - Shared chrome

extension View {
    /// Hover / keyboard-selection well that bleeds 4 pt into the card padding, so marks stay aligned with the header.
    func rowChrome(hovered: Bool, isSelected: Bool, isKeyboardFocused: Bool) -> some View {
        modifier(RowChrome(hovered: hovered, isSelected: isSelected, isKeyboardFocused: isKeyboardFocused))
    }
}

private extension View {
    func eventAccessibility(row: Agenda.Row, context: EventRowContext) -> some View {
        modifier(EventAccessibility(row: row, context: context))
    }
}

private struct RowChrome: ViewModifier {
    @Environment(\.cranny) private var theme
    let hovered: Bool
    let isSelected: Bool
    let isKeyboardFocused: Bool

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: Radius.chip, style: .continuous)
        let selected = isSelected && isKeyboardFocused
        let fill: Color = selected ? theme.palette.controlPressed : hovered ? theme.palette.control : .clear
        content
            .padding(.horizontal, Space.xs)
            .background(shape.fill(fill))
            .crannyFocusRing(selected, radius: Radius.chip)
            .padding(.horizontal, -Space.xs)
            .contentShape(Rectangle())
            .animation(theme.animation(.hover), value: hovered)
    }
}

private struct EventAccessibility: ViewModifier {
    let row: Agenda.Row
    let context: EventRowContext

    func body(content: Content) -> some View {
        let event = row.event
        let link = context.model.link(for: event)
        content
            .onTapGesture { context.model.openInCalendar(event) }
            .help(tooltip)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(CalendarFormat.title(event, redacted: context.redacted)))
            .accessibilityValue(Text(value))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { context.model.openInCalendar(event) }
            .accessibilityAction(named: Text(CalendarStrings.openInCalendar)) { context.model.openInCalendar(event) }
            .modifier(JoinAction(present: link != nil) { context.model.join(event) })
    }

    private var value: String {
        let event = row.event
        let time = row.role == .allDay ? CalendarFormat.allDay : CalendarFormat.timeRange(event.start, event.end)
        switch row.role {
        case .live:
            let left = CalendarFormat.spokenTimeLeft(minutes: max(MinuteMath.minutesUntil(event.end, from: context.model.currentTime), 1))
            return String(localized: "Now, \(left), \(time)", bundle: .module, comment: "VoiceOver: an event in progress (\"Now, 12 minutes left, 10:30–11:00\")")
        case .ended:
            return String(localized: "Ended, \(time)", bundle: .module, comment: "VoiceOver: an event that is over (\"Ended, 9:00–9:30\")")
        default:
            return time
        }
    }

    private var tooltip: String {
        let event = row.event
        return CalendarFormat.subtitle(event, link: context.model.link(for: event), redacted: context.redacted)
    }
}

/// "Join meeting" as a named VoiceOver action, only when there is a link.
private struct JoinAction: ViewModifier {
    let present: Bool
    let perform: @MainActor () -> Void
    func body(content: Content) -> some View {
        if present {
            content.accessibilityAction(named: Text("Join meeting", bundle: .module, comment: "Calendar: Join button, VoiceOver label")) { perform() }
        } else {
            content
        }
    }
}

#Preview("Event rows") {
    let services = CrannyServices.preview()
    let model = CalendarModel.sample(services: services)
    let now = model.scheduler.now
    let agenda = Agenda.make(events: model.store.events, day: EventWindow.day(offset: 0, from: now, calendar: .autoupdatingCurrent),
                             now: now, isToday: true, showsPastToday: true, soonID: model.scheduler.state.soon?.event.id)
    let context = EventRowContext(model: model, isToday: true, redacted: false, isSelected: false, isKeyboardFocused: false)
    VStack(alignment: .leading, spacing: 2) {
        ForEach(agenda.rows) { row in
            if agenda.isFeatured(row) { FeaturedEventRow(row: row, context: context) } else { EventRow(row: row, context: context) }
        }
    }
    .crannyCard(cells: 3)
    .padding()
    .background(.black)
    .crannyThemeRoot(CrannyTheme())
}
