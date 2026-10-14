// CrannyCalendar/UI/Widget/EventRow.swift — one event in the widget (DESIGN.md §7.2). Ordinary rows are one
// 18-pt line: calendar capsule · title (`caption`) · start time (`caption`, mono, secondary). The live or next
// event is featured on two lines — title, then "Now · 12m left" / "In 4m" in the event colour — with Join when it
// has a link; while one is live, the meeting "Meeting soon" announces is featured as well. Today's ended events are tertiary and struck through (not dimmed alone, §16).
// A featured row picks the first `FeaturedRowLayout` that fits, so Join keeps its word (§16) wherever a layout with
// the word fits: beside both lines, else on the title line.
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

/// How a featured row fits its trailing part — Join, or the start time when there is no link — beside its two
/// lines. `FeaturedEventRow` offers them to `ViewThatFits` in this order, then `overflow` when none fits.
enum FeaturedRowLayout: CaseIterable {
    /// Join (glyph and word) or the start time beside both lines: the layout of DESIGN.md §7.2.
    case roomy
    /// Join or the start time on the title line (the title truncates first), so "Now · 12m left" gets the row's
    /// full width: a 3-cell row in Russian.
    case stacked
    /// Last resort: Join keeps only its glyph (its VoiceOver label and tooltip still say "Join meeting") and the
    /// start time goes; the second line matters more.
    case compact

    var showsJoinWord: Bool { self != .compact }

    /// When even the second line is wider than the row, it is cut short whatever the layout: the stacked layout
    /// cuts it least and keeps Join's word. (`ViewThatFits` shows its last child when none fits.)
    static let overflow = FeaturedRowLayout.stacked

    /// The title's ideal width, which decides whether the layout fits: a comfortable ten characters beside both
    /// lines; on the title line it may shrink to about seven before Join gives up its word (the full title is in the
    /// tooltip and VoiceOver).
    var titleIdealWidth: CGFloat { self == .stacked ? 44 : 64 }
}

struct FeaturedEventRow: View {
    @State private var hovered = false
    let row: Agenda.Row
    let context: EventRowContext

    var body: some View {
        let event = row.event
        MinuteClock(anchor: row.role == .live ? event.end : event.start) { tick in
            FeaturedRowChoice { layout($0, tick: tick) }
        }
        .rowChrome(hovered: hovered, isSelected: context.isSelected, isKeyboardFocused: context.isKeyboardFocused)
        .onHover { hovered = $0 }
        .eventAccessibility(row: row, context: context)
    }

    private func layout(_ layout: FeaturedRowLayout, tick: Date) -> FeaturedRowBody {
        let event = row.event
        let now = context.model.displayNow(tick)
        let status = row.role == .live
            ? CalendarFormat.nowWithTimeLeft(minutes: max(MinuteMath.minutesUntil(event.end, from: now), 1))
            : CalendarFormat.startsIn(minutes: max(MinuteMath.minutesUntil(event.start, from: now), 1))
        let model = context.model
        var join: (@MainActor () -> Void)?
        if model.link(for: event) != nil { join = { model.join(event) } }
        return FeaturedRowBody(layout: layout, title: CalendarFormat.title(event, redacted: context.redacted), status: status,
                               color: event.color, start: CalendarFormat.time(event.start), join: join)
    }
}

/// The first `FeaturedRowLayout` that fits, else `overflow`. (`ViewThatFits` needs distinct children: positional
/// ones, not a `ForEach` that repeats an id.)
struct FeaturedRowChoice<Row: View>: View {
    let row: (FeaturedRowLayout) -> Row

    var body: some View {
        ViewThatFits(in: .horizontal) {                                       // `FeaturedRowLayout.allCases`, then `overflow`
            row(.roomy)
            row(.stacked)
            row(.compact)
            row(FeaturedRowLayout.overflow)
        }
    }
}

/// One `FeaturedRowLayout` of a featured row, from its words alone (tests measure it in every language of the catalog).
struct FeaturedRowBody: View {
    @Environment(\.cranny) private var theme
    let layout: FeaturedRowLayout
    let title: String
    /// "Now · 12m left" / "In 4m".
    let status: String
    let color: RGB
    /// The start time, shown instead of Join when the event has no link (not in the compact layout).
    let start: String
    let join: (@MainActor () -> Void)?

    var body: some View {
        HStack(spacing: Space.s) {
            CalendarMark(color: color, height: 28)
            switch layout {
            case .roomy:
                VStack(alignment: .leading, spacing: 1) {
                    titleText
                    statusText
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let join { JoinButton(size: .row(word: true), action: join) } else { startText }
            case .stacked:
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: Space.s) {
                        titleText
                        if let join { JoinButton(size: .titleLine, action: join) } else { startText }
                    }
                    .frame(height: JoinButton.titleLineHeight)
                    statusText
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            case .compact:
                VStack(alignment: .leading, spacing: 1) {
                    titleText
                    statusText
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let join { JoinButton(size: .row(word: false), action: join) }
            }
        }
        .frame(height: AgendaScroll.featuredHeight)
    }

    private var titleText: some View {
        Text(title)
            .crannyFont(.caption).fontWeight(.semibold)
            .foregroundStyle(theme.palette.label)
            .lineLimit(1)
            .frame(minWidth: 0, idealWidth: layout.titleIdealWidth, maxWidth: .infinity, alignment: .leading)
    }

    private var statusText: some View {
        Text(status)
            .crannyFont(.caption)
            .foregroundStyle(theme.eventColor(color))
            .lineLimit(1)
            .contentTransition(.numericText(countsDown: true))
            .animation(theme.animation(.contentSwap), value: status)
    }

    private var startText: some View {
        Text(start)
            .crannyFont(.caption)
            .foregroundStyle(theme.palette.secondaryLabel)
            .fixedSize()
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
