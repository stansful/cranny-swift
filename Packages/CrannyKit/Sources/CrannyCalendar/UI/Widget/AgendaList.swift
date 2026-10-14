// CrannyCalendar/UI/Widget/AgendaList.swift — the scrolling list of one day (DESIGN.md §7.2: "a 12-pt fade mask
// at the bottom; '+3 more' in caption"). When the live or next event would start below the fold it opens
// scrolled to it, so a busy morning (or a few all-day events) never hides the meeting that matters. Lists never
// stagger (§4.5).
import CrannyCore
import Foundation
import SwiftUI

struct AgendaList: View {
    @Environment(\.cranny) private var theme
    let agenda: Agenda
    let model: CalendarModel
    let redacted: Bool
    /// The keyboard selection (↑ ↓), drawn only while the list has keyboard focus.
    let selection: String?
    let isKeyboardFocused: Bool

    /// Row bottoms in the viewport's coordinates, for the fade and "+N more".
    @State private var rowBottoms: [String: CGFloat] = [:]
    @State private var viewport: CGFloat = 0
    @State private var contentHeight: CGFloat = 0
    private let space = "calendar.agenda"

    var body: some View {
        let overflows = contentHeight > viewport + 0.5
        let hidden = agenda.rows.filter { (rowBottoms[$0.id] ?? 0) > viewport + 1 }
        VStack(alignment: .leading, spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    rows
                        .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { contentHeight = $0 }
                }
                .coordinateSpace(.named(space))
                .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { viewport = $0 }
                .mask { fadeMask(active: overflows && !hidden.isEmpty) }
                .task(id: ScrollAnchor(day: agenda.day, featured: agenda.featuredID, measured: viewport > 0)) { revealFeatured(proxy) }
                .onChange(of: selection) { _, id in
                    guard let id else { return }
                    withAnimation(theme.animation(.listReorder)) { proxy.scrollTo(id) }
                }
                if overflows {
                    MoreFooter(count: hidden.count) {
                        if let first = hidden.first { withAnimation(theme.animation(.listReorder)) { proxy.scrollTo(first.id, anchor: .bottom) } }
                    }
                }
            }
        }
    }

    private var rows: some View {
        VStack(alignment: .leading, spacing: Space.xxs) {
            ForEach(agenda.rows) { row in
                let context = EventRowContext(model: model, isToday: agenda.isToday, redacted: redacted,
                                              isSelected: selection == row.id, isKeyboardFocused: isKeyboardFocused)
                Group {
                    if row.id == agenda.featuredID {
                        FeaturedEventRow(row: row, context: context)
                    } else {
                        EventRow(row: row, context: context)
                    }
                }
                .id(row.id)
                .onGeometryChange(for: CGFloat.self, of: { $0.frame(in: .named(space)).maxY }) { rowBottoms[row.id] = $0 }
            }
        }
    }

    /// Opaque, then a 12-pt fade at the bottom while rows hide below it.
    private func fadeMask(active: Bool) -> some View {
        VStack(spacing: 0) {
            Rectangle()
            LinearGradient(colors: [.black, .black.opacity(active ? 0 : 1)], startPoint: .top, endPoint: .bottom)
                .frame(height: 12)
        }
    }

    /// Scrolls the featured row to the top when it (or its second line) would not be fully visible; otherwise
    /// leaves the list at its start so the day reads from the top.
    private func revealFeatured(_ proxy: ScrollViewProxy) {
        guard viewport > 0, let id = agenda.featuredID, let index = agenda.rows.firstIndex(where: { $0.id == id }), index > 0 else { return }
        let heightAbove = CGFloat(index) * (18 + Space.xxs)                  // rows above the featured one are single lines
        if heightAbove + 32 > viewport - 12 { proxy.scrollTo(id, anchor: .top) }
    }
}

/// When the list re-anchors: a new day, or a different live / next event.
private struct ScrollAnchor: Equatable {
    var day: DateInterval
    var featured: String?
    var measured: Bool
}

/// "+3 more" under the list; clicking it scrolls to the first hidden row. Keeps its line while the list
/// overflows, so scrolling to the end does not make the list jump.
private struct MoreFooter: View {
    @Environment(\.cranny) private var theme
    let count: Int
    let action: @MainActor () -> Void

    var body: some View {
        HStack {
            if count > 0 {
                Button(action: action) {
                    Text("+\(count) more", bundle: .module, comment: "Calendar widget: events below the visible list (\"+3 more\")")
                        .crannyFont(.caption)
                        .foregroundStyle(theme.palette.tertiaryLabel)
                        .contentTransition(.numericText())
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, 3 + Space.s)                                       // aligned with the titles
        .frame(height: 14)
        .animation(theme.animation(.contentSwap), value: count)
    }
}

#Preview("Agenda · busy day") {
    let services = CrannyServices.preview()
    let model = CalendarModel.sample(services: services)
    let now = model.scheduler.now
    let agenda = Agenda.make(events: model.store.events, day: EventWindow.day(offset: 0, from: now, calendar: .autoupdatingCurrent),
                             now: now, isToday: true, showsPastToday: true)
    AgendaList(agenda: agenda, model: model, redacted: false, selection: nil, isKeyboardFocused: false)
        .frame(height: 74)
        .crannyCard(cells: 3)
        .padding()
        .background(.black)
        .crannyThemeRoot(CrannyTheme())
}
