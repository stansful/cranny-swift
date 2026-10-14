// CrannyNotchUI/Peek/PeekView.swift — the rows of a peek (DESIGN.md §9.3): below the band row, one 52-pt row
// per activity (at most 4), laid out as [12] [the activity's `peekRow()`] [12], then 8 pt at the bottom.
// Rows enter top to bottom, 30 ms apart; a click opens the panel focused on that activity's widget.
import CrannyCore
import SwiftUI

struct PeekRows: View {
    @Environment(\.cranny) private var theme
    let model: NotchSceneModel
    let registry: ModuleRegistry
    let actions: NotchUIActions

    /// At most four rows are drawn (DESIGN.md §9.4); the shape has room for exactly these.
    static let maximumRows = 4

    var body: some View {
        let shape = model.layout.peek(rows: max(model.peekRows.count, 1))
        VStack(spacing: 0) {
            ForEach(Array(model.peekRows.prefix(Self.maximumRows).enumerated()), id: \.element) { index, id in
                if let activity = model.activity(id, in: registry) {
                    PeekRow(id: id, activity: activity, actions: actions)
                        .staggeredReveal(delay: ContentTiming.peekRowDelay(index: index, reduceMotion: theme.reduceMotion))
                }
            }
        }
        .padding(.bottom, PeekRows.bottomInset)
        .frame(width: shape.bodyWidth, alignment: .top)
    }

    /// Space under the last row (`NotchLayout.peek`: rows of 52 + 8).
    static let bottomInset: CGFloat = 8
}

/// One row: the activity draws `[visual 40] [title / subtitle] [≤ 3 controls]`; the canvas adds the 12-pt
/// margins, the 52-pt height, the click target and the VoiceOver element.
private struct PeekRow: View {
    @Environment(\.cranny) private var theme
    @State private var hovered = false
    let id: ActivityID
    let activity: any LiveActivity
    let actions: NotchUIActions

    var body: some View {
        activity.view(for: .peekRow)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: NotchLayout.peekRow)
            .padding(.horizontal, Space.l)
            .background {
                RoundedRectangle(cornerRadius: Radius.concentric(Radius.peek, inset: Space.xs), style: .continuous)
                    .fill(hovered ? theme.palette.control.opacity(0.5) : .clear)
                    .padding(.horizontal, Space.xs)
            }
            .contentShape(Rectangle())
            .onTapGesture { actions.activityTapped(id) }
            .onHover { hovered = $0 }
            .animation(theme.animation(.hover), value: hovered)
            .activityAccessibility(activity, id: id, open: { actions.activityTapped(id) },
                                   dismiss: { actions.dismissActivity(id) })
    }
}

#Preview("Peek · one row") {
    let (model, registry) = previewScene(.peek)
    NotchCanvasView(model: model, registry: registry)
        .frame(width: 560, height: 140)
        .background(Color(white: 0.25))
}

#Preview("Peek · three rows") {
    let (model, registry) = previewScene(.peek, peekRowCount: 3)
    NotchCanvasView(model: model, registry: registry)
        .frame(width: 560, height: 240)
        .background(Color(white: 0.25))
}
