// CrannyCalendar/UI/Widget/DayHeader.swift — the widget's first line (DESIGN.md §7.2): weekday (`micro`, red for
// today) + date (`headline`), "+N more" while the list below overflows, and on the trailing side ‹ › (3 cells) or
// the day strip (≥ 4 cells). The header is 16 pt tall; its 28-pt buttons overhang into the card padding so the
// list keeps its room. The weekday and the day number are never cut short: to make room the date shortens first
// ("14 October" → "14 Oct" → "14"), then "+N more" (→ "+N" → gone), and last the weekday (`DayHeaderLine`).
import CrannyCore
import Foundation
import SwiftUI

struct DayHeader<Trailing: View>: View {
    @Environment(\.locale) private var locale
    let date: Date
    let isToday: Bool
    /// Rows hidden below the list (nil = the list fits: no "+N more").
    let more: Int?
    let showMore: @MainActor () -> Void
    private let trailing: Trailing

    init(date: Date, isToday: Bool, more: Int? = nil, showMore: @escaping @MainActor () -> Void = {},
         @ViewBuilder trailing: () -> Trailing) {
        self.date = date; self.isToday = isToday; self.more = more; self.showMore = showMore; self.trailing = trailing()
    }

    var body: some View {
        let dates = DayHeaderLine.Dates(date, locale: locale)
        HStack(spacing: Space.xs) {
            DayHeaderChoice { line in
                DayHeaderLineBody(line: line, date: date, dates: dates, isToday: isToday, more: more, showMore: showMore)
            }
            trailing
        }
        .frame(height: 16)
    }
}

/// `ViewThatFits` over the `DayHeaderLine`s in order: the first whose ideal width fits, else the last.
struct DayHeaderChoice<Line: View>: View {
    let line: (DayHeaderLine) -> Line

    var body: some View {
        ViewThatFits(in: .horizontal) {                                       // `DayHeaderLine.allCases`, in order
            line(.full)
            line(.shortMonth)
            line(.dayOnly)
            line(.countOnly)
            line(.noMore)
            line(.shortWeekday)
        }
    }
}

/// The header line's variants, in the order the header tries them (`DayHeaderChoice`: the first whose ideal width
/// fits beside ‹ › or the strip, else the last). Every variant shows the weekday and the day number in full; only the
/// month, "+N more" and the weekday's length give way. Measured in every language by `DayHeaderFitTests`.
enum DayHeaderLine: CaseIterable {
    /// "TUE 14 October   +3 more".
    case full
    /// "TUE 14 Oct   +3 more".
    case shortMonth
    /// "TUE 14   +3 more": the 3-cell header in most languages.
    case dayOnly
    /// "TUE 14   +3": the count keeps its place (VoiceOver and the tooltip still say "+3 more").
    case countOnly
    /// "TUE 14": no room for the count either; the list still scrolls (a 5-cell column beside ‹ ›).
    case noMore
    /// "QUA. 14": last resort for a weekday whose abbreviation is a whole word (pt-PT "quarta", pl "niedz.").
    case shortWeekday

    var date: KeyPath<DayHeaderLine.Dates, String> {
        switch self {
        case .full: \.dayMonth
        case .shortMonth: \.dayMonthShort
        case .dayOnly, .countOnly, .noMore, .shortWeekday: \.dayNumber
        }
    }
    var more: MoreEventsButton.Style? {
        switch self {
        case .full, .shortMonth, .dayOnly: .words
        case .countOnly: .count
        case .noMore, .shortWeekday: nil
        }
    }
    var shortWeekday: Bool { self == .shortWeekday }

    /// The day's texts in the header's locale, formatted once for all the lines.
    struct Dates {
        let weekday, weekdayShort, dayMonth, dayMonthShort, dayNumber: String

        init(_ date: Date, locale: Locale) {
            weekday = CalendarFormat.weekday(date, locale: locale)
            weekdayShort = CalendarFormat.weekdayShort(date, locale: locale)
            dayMonth = CalendarFormat.dayMonth(date, locale: locale)
            dayMonthShort = CalendarFormat.dayMonthShort(date, locale: locale)
            dayNumber = CalendarFormat.dayNumber(date, locale: locale)
        }

        /// Texts as given: `DayHeaderFitTests` pins a language whose forms differ between macOS releases' locale data.
        init(weekday: String, weekdayShort: String, dayMonth: String, dayMonthShort: String, dayNumber: String) {
            self.weekday = weekday; self.weekdayShort = weekdayShort; self.dayMonth = dayMonth
            self.dayMonthShort = dayMonthShort; self.dayNumber = dayNumber
        }
    }
}

/// One `DayHeaderLine`: the weekday and date (never cut short), then "+N more" against the trailing edge.
struct DayHeaderLineBody: View {
    @Environment(\.cranny) private var theme
    let line: DayHeaderLine
    let date: Date
    let dates: DayHeaderLine.Dates
    let isToday: Bool
    let more: Int?
    var showMore: @MainActor () -> Void = {}

    var body: some View {
        HStack(spacing: Space.xs) {
            HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                Text(line.shortWeekday ? dates.weekdayShort : dates.weekday)
                    .crannyFont(.micro)
                    .foregroundStyle(isToday ? theme.palette.danger : theme.palette.secondaryLabel)
                Text(dates[keyPath: line.date])
                    .crannyFont(.headline)
                    .foregroundStyle(theme.palette.label)
            }
            .lineLimit(1)
            .fixedSize()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(CalendarFormat.fullDate(date)))
            .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            if let more, let style = line.more { MoreEventsButton(count: more, style: style, action: showMore) }
        }
    }
}

/// ‹ › within days behind / ahead. Hidden when there is nowhere to page (a single day, or 5 cells showing the
/// whole two-day window). `columns`: days shown side by side; paging moves them together. `chevron.backward` /
/// `chevron.forward` point the way the days run: right to left the previous day is the right-hand ›.
struct DayPager: View {
    let model: CalendarModel
    var columns = 1

    var body: some View {
        let back = model.canPage(-1, columns: columns), forward = model.canPage(1, columns: columns)
        if back || forward {
            HStack(spacing: 0) {
                pagerButton("chevron.backward", label: String(localized: "Previous day", bundle: .module, comment: "Calendar widget: page to the previous day (button label)"),
                            enabled: back) { model.page(-1, columns: columns) }
                pagerButton("chevron.forward", label: String(localized: "Next day", bundle: .module, comment: "Calendar widget: page to the next day (button label)"),
                            enabled: forward) { model.page(1, columns: columns) }
            }
            .frame(height: 16)
        }
    }

    /// The glyph size comes from `CrannyIconButtonStyle` (13 pt at the 28-pt hit size, DESIGN.md §14.1).
    private func pagerButton(_ symbol: String, label: String, enabled: Bool, action: @escaping @MainActor () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
        }
        .buttonStyle(CrannyIconButtonStyle(.plain, size: HitTarget.preferred))
        .frame(width: HitTarget.preferred, height: 16)
        .disabled(!enabled)
        .accessibilityLabel(Text(label))
        .help(label)
    }
}

/// One chip per day of the window; today is a white capsule with black text (DESIGN.md §7.2).
struct DayStrip: View {
    let model: CalendarModel
    let today: Date

    var body: some View {
        let chips = HStack(spacing: 0) {
            ForEach(Array(model.dayRange), id: \.self) { offset in
                DayChip(date: EventWindow.day(offset: offset, from: today, calendar: model.store.clock.calendar()).start,
                        isToday: offset == 0, isSelected: offset == model.selectedOffset) {
                    model.selectDay(offset)
                }
            }
        }
        ViewThatFits(in: .horizontal) {
            chips
            ScrollView(.horizontal, showsIndicators: false) { chips }
        }
        .frame(height: 16)
    }
}

private struct DayChip: View {
    @Environment(\.cranny) private var theme
    @State private var hovered = false
    let date: Date
    let isToday: Bool
    let isSelected: Bool
    let action: @MainActor () -> Void

    var body: some View {
        let p = theme.palette
        // Today: the white capsule with the label colour Core derives for a filled surface (black).
        let fill: Color = isToday ? RGB.white.color : isSelected ? p.controlPressed : hovered ? p.control : .clear
        Button(action: action) {
            Text(CalendarFormat.dayNumber(date))
                .crannyFont(.caption).fontWeight(.semibold)
                .foregroundStyle(isToday ? RGB.white.onColor.color : isSelected ? p.label : p.secondaryLabel)
                .frame(minWidth: 22, minHeight: 18)
                .background(Capsule(style: .continuous).fill(fill))
                .overlay {
                    // The selected day (other than today, which is white) also gets a ring: selection is not
                    // carried by a fill shade alone (Differentiate Without Color).
                    if isSelected && !isToday {
                        Capsule(style: .continuous).strokeBorder(p.stroke, lineWidth: 1)
                    }
                }
                .frame(width: HitTarget.preferred, height: HitTarget.nook.height)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(height: 16)
        .onHover { hovered = $0 }
        .animation(theme.animation(.hover), value: hovered)
        .accessibilityLabel(Text(CalendarFormat.fullDate(date)))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .help(CalendarFormat.fullDate(date))
    }
}

#Preview("Day header · pager and strip") {
    let services = CrannyServices.preview()
    services.settings[CalendarSettings.daysBehind] = 2
    services.settings[CalendarSettings.daysAhead] = 3
    let model = CalendarModel.sample(services: services)
    return VStack(alignment: .leading, spacing: Space.xl) {
        DayHeader(date: Date(), isToday: true) { DayPager(model: model) }
            .frame(width: 160)
        DayHeader(date: Date(), isToday: true) { DayStrip(model: model, today: Date()) }
            .frame(width: 224)
    }
    .padding()
    .crannyCard(cells: 5)
    .padding()
    .background(.black)
    .crannyThemeRoot(CrannyTheme())
}
