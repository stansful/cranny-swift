// CrannyCalendar/UI/Widget/DayHeader.swift — the widget's first line (DESIGN.md §7.2): weekday (`micro`, red for
// today) + date (`headline`), "+N more" while the list below overflows, and on the trailing side ‹ › (3 cells) or
// the day strip (≥ 4 cells). The header is 16 pt tall; its 28-pt buttons overhang into the card padding so the
// list keeps its room. The date shortens ("14 October" → "14 Oct" → "14") to make room.
import CrannyCore
import Foundation
import SwiftUI

struct DayHeader<Trailing: View>: View {
    @Environment(\.cranny) private var theme
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
        HStack(spacing: Space.xs) {
            HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                Text(CalendarFormat.weekday(date))
                    .crannyFont(.micro)
                    .foregroundStyle(isToday ? theme.palette.danger : theme.palette.secondaryLabel)
                // "14 October", "14 Oct", or just "14" when ‹ › or the strip leave too little room.
                ViewThatFits(in: .horizontal) {
                    dateText(CalendarFormat.dayMonth(date))
                    dateText(CalendarFormat.dayMonthShort(date))
                    dateText(CalendarFormat.dayNumber(date))
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(CalendarFormat.fullDate(date)))
            .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            if let more { MoreEventsButton(count: more, action: showMore) }
            trailing
        }
        .frame(height: 16)
    }

    private func dateText(_ text: String) -> some View {
        Text(text)
            .crannyFont(.headline)
            .foregroundStyle(theme.palette.label)
            .lineLimit(1)
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
