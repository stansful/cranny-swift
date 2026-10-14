// CrannyCalendar/UI/Widget/AgendaList.swift — the scrolling list of one day (DESIGN.md §7.2). The list keeps the
// whole height under the header, so three rows fit at the default size (one of them on two lines); "+N more"
// sits in the header line (`DayHeader`) instead of taking a line of its own. A 12-pt fade covers only a row that
// is partly out of view, never a row that can be read in full. The list opens at the top and scrolls only when a
// featured row would otherwise be clipped — just far enough, and never leaving a sliver of the row above. Lists
// never stagger (§4.5).
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
    /// Rows not fully visible below the list, for the header's "+N more": nil while everything fits.
    @Binding var hiddenBelow: Int?
    /// Bumped by the header's "+N more": scroll the first hidden row into view.
    let revealRequest: Int

    @State private var viewport: CGFloat = 0
    /// The top of the content in the viewport's coordinates (< 0 once scrolled).
    @State private var contentTop: CGFloat = 0
    private let viewportSpace = "calendar.agenda.viewport"

    var body: some View {
        let frames = AgendaScroll.frames(agenda)
        let layout = ListLayout(rows: frames, viewport: viewport, contentTop: contentTop)
        let overflows = viewport > 0 && (frames.last?.frame.maxY ?? 0) > viewport + 0.5
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                rows
                    .onGeometryChange(for: CGFloat.self, of: { $0.frame(in: .named(viewportSpace)).minY }) { contentTop = $0 }
            }
            .coordinateSpace(.named(viewportSpace))
            .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { viewport = $0 }
            .mask { fadeMask(layout) }
            .task(id: ScrollAnchor(day: agenda.day, featured: agenda.featuredIDs, viewport: viewport)) {
                // A new day or new featured rows: from the top, unless a featured row would be clipped there.
                guard viewport > 0 else { return }
                if let target = AgendaScroll.target(rows: frames, featured: agenda.featuredIDs, viewport: viewport) {
                    proxy.scrollTo(target.id, anchor: target.anchor == .top ? .top : .bottom)
                } else if let first = agenda.rows.first {
                    proxy.scrollTo(first.id, anchor: .top)
                }
            }
            .onChange(of: selection) { _, id in
                guard let id else { return }
                withAnimation(theme.animation(.listReorder)) { proxy.scrollTo(id) }
            }
            .onChange(of: revealRequest) { _, _ in
                guard let first = layout.hiddenBelow.first else { return }
                withAnimation(theme.animation(.listReorder)) { proxy.scrollTo(first, anchor: .bottom) }
            }
            .onChange(of: overflows ? layout.hiddenBelow.count : nil, initial: true) { _, count in
                hiddenBelow = count
            }
        }
    }

    private var rows: some View {
        VStack(alignment: .leading, spacing: AgendaScroll.spacing) {
            ForEach(agenda.rows) { row in
                let context = EventRowContext(model: model, isToday: agenda.isToday, redacted: redacted,
                                              isSelected: selection == row.id, isKeyboardFocused: isKeyboardFocused)
                Group {
                    if agenda.isFeatured(row) {
                        FeaturedEventRow(row: row, context: context)
                    } else {
                        EventRow(row: row, context: context)
                    }
                }
                .id(row.id)
            }
        }
    }

    /// At each edge: a sliver of a cut-off row is hidden, a peek is faded over at most 12 pt.
    private func fadeMask(_ layout: ListLayout) -> some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: layout.top.hidden)
            LinearGradient(colors: [.black.opacity(0), .black], startPoint: .top, endPoint: .bottom)
                .frame(height: layout.top.fade)
            Rectangle()
            LinearGradient(colors: [.black, .black.opacity(0)], startPoint: .top, endPoint: .bottom)
                .frame(height: layout.bottom.fade)
            Color.clear.frame(height: layout.bottom.hidden)
        }
    }
}

/// A row's top and bottom in the content's coordinates.
nonisolated struct RowFrame: Equatable, Sendable {
    var minY: CGFloat
    var maxY: CGFloat
}

/// What is visible at a scroll position: how each edge treats a row it cuts, and the rows hidden below.
nonisolated struct ListLayout {
    /// The mask at one edge: `hidden` pt fully masked (next to the edge), then `fade` pt of gradient.
    nonisolated struct Edge: Equatable, Sendable {
        var hidden: CGFloat = 0
        var fade: CGFloat = 0
    }

    let top: Edge
    let bottom: Edge
    /// Rows not fully visible below the viewport, in order.
    let hiddenBelow: [String]

    static let fade: CGFloat = 12

    /// - Parameters: rows in list order with their content frames; `contentTop` ≤ 0 once scrolled.
    init(rows: [(id: String, frame: RowFrame)], viewport: CGFloat, contentTop: CGFloat) {
        guard viewport > 0 else { top = Edge(); bottom = Edge(); hiddenBelow = []; return }
        let visible = rows.map { (id: $0.id, top: $0.frame.minY + contentTop, bottom: $0.frame.maxY + contentTop) }
        let cutAtTop = visible.first { $0.top < -0.5 && $0.bottom > 0.5 }.map(\.bottom) ?? 0
        let cutAtBottom = visible.first { $0.top < viewport - 0.5 && $0.bottom > viewport + 0.5 }.map { viewport - $0.top } ?? 0
        top = Self.edge(cutAtTop)
        bottom = Self.edge(cutAtBottom)
        hiddenBelow = visible.filter { $0.bottom > viewport + 0.5 }.map(\.id)
    }

    /// A cut part shorter than `AgendaScroll.minimumPeek` is a sliver (a glitch): hidden. A longer one is a peek
    /// ("more this way"): faded over its last 12 pt.
    private static func edge(_ cut: CGFloat) -> Edge {
        guard cut > 0.5 else { return Edge() }
        return cut < AgendaScroll.minimumPeek ? Edge(hidden: cut) : Edge(fade: min(fade, cut))
    }
}

/// Row geometry and where the list scrolls when it opens (pure, tested). Rows have fixed heights, so their
/// frames are known without measuring.
nonisolated enum AgendaScroll {
    nonisolated enum Anchor: Sendable { case top, bottom }
    static let rowHeight: CGFloat = 18
    static let featuredHeight: CGFloat = 32
    static let spacing: CGFloat = Space.xxs
    /// Less of the row above than this is scrolled away instead of left as a sliver.
    static let minimumPeek: CGFloat = 10

    static func frames(_ agenda: Agenda) -> [(id: String, frame: RowFrame)] {
        var top: CGFloat = 0
        return agenda.rows.map { row in
            let height = agenda.isFeatured(row) ? featuredHeight : rowHeight
            defer { top += height + spacing }
            return (row.id, RowFrame(minY: top, maxY: top + height))
        }
    }

    /// nil = stay at the top (every featured row is fully visible there). Otherwise scroll just far enough to show
    /// the featured rows in full, and on to the next row boundary when that would leave less than `minimumPeek`
    /// of the row above (a sliver reads as a glitch, a peek reads as "more above").
    static func target(rows: [(id: String, frame: RowFrame)], featured: [String], viewport: CGFloat) -> (id: String, anchor: Anchor)? {
        let block = rows.filter { featured.contains($0.id) }
        guard viewport > 0, let first = block.first, let last = block.last, last.frame.maxY > viewport + 0.5 else { return nil }
        // Taller than the list: show the first featured row from its top.
        guard last.frame.maxY - first.frame.minY <= viewport + 0.5 else { return (first.id, .top) }
        let offset = last.frame.maxY - viewport
        if let cut = rows.first(where: { $0.frame.minY < offset - 0.5 && $0.frame.maxY > offset + 0.5 }),
           cut.frame.maxY - offset < minimumPeek,
           let next = rows.first(where: { $0.frame.minY >= cut.frame.maxY - 0.5 }) {
            return (next.id, .top)
        }
        return (last.id, .bottom)
    }
}

/// When the list re-anchors: a new day, different featured rows, or a new height.
private struct ScrollAnchor: Equatable {
    var day: DateInterval
    var featured: [String]
    var viewport: CGFloat
}

/// "+3 more" in the header line: clicking it scrolls to the first hidden row. While the list overflows it keeps
/// its place (invisible when nothing is hidden below), so the date beside it does not change as the list scrolls.
struct MoreEventsButton: View {
    /// "+3 more", or "+3" where the header line has no room for the word (`DayHeaderLine.countOnly`).
    enum Style { case words, count }

    @Environment(\.cranny) private var theme
    @Environment(\.locale) private var locale
    let count: Int
    var style = Style.words
    let action: @MainActor () -> Void

    var body: some View {
        let words = Text("+\(max(count, 1)) more", bundle: .module, comment: "Calendar widget: events below the visible list (\"+3 more\")")
        Button(action: action) {
            Group {
                switch style {
                case .words: words
                case .count: Text(verbatim: max(count, 1).formatted(.number.sign(strategy: .always()).locale(locale)))  // "+3", "+٣"
                }
            }
            .crannyFont(.caption)
            .foregroundStyle(theme.palette.tertiaryLabel)
            .lineLimit(1)
            .fixedSize()
            .contentTransition(.numericText())
            .frame(minWidth: HitTarget.nook.width, minHeight: HitTarget.nook.height)
            .contentShape(Rectangle())                                    // 28 × 24 hit area around a 14-pt line
        }
        .buttonStyle(.plain)
        .accessibilityLabel(words)                                        // "+3 more" also where it shows "+3"
        .help(style == .count ? words : Text(verbatim: ""))
        .frame(height: 16)
        .opacity(count > 0 ? 1 : 0)
        .disabled(count == 0)
        .accessibilityHidden(count == 0)
        .animation(theme.animation(.contentSwap), value: count)
    }
}

#Preview("Agenda · busy day") {
    let services = CrannyServices.preview()
    let model = CalendarModel.sample(services: services)
    let now = model.scheduler.now
    let agenda = Agenda.make(events: model.store.events, day: EventWindow.day(offset: 0, from: now, calendar: .autoupdatingCurrent),
                             now: now, isToday: true, showsPastToday: true, soonID: model.scheduler.state.soon?.event.id)
    AgendaList(agenda: agenda, model: model, redacted: false, selection: nil, isKeyboardFocused: false,
               hiddenBelow: .constant(nil), revealRequest: 0)
        .frame(height: 74)
        .crannyCard(cells: 3)
        .padding()
        .background(.black)
        .crannyThemeRoot(CrannyTheme())
}
