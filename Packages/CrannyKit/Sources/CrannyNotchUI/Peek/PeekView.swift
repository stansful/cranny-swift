// CrannyNotchUI/Peek/PeekView.swift — compact row + one 52-pt row per activity (DESIGN.md §9.3).
// WP0 skeleton: rows draw each activity's `peekRow()`; WP12 adds the 30-ms stagger and matched geometry.
import CrannyCore
import SwiftUI

struct PeekView: View {
    @Environment(\.cranny) private var theme
    let model: NotchSceneModel
    let registry: ModuleRegistry
    let actions: NotchUIActions

    var body: some View {
        let layout = model.layout
        let shape = layout.peek(rows: max(model.peekRows.count, 1))
        VStack(spacing: 0) {
            if let id = model.primary, let primary = model.activity(id, in: registry) {
                CompactRow(layout: layout, activity: primary)
            } else {
                Color.clear.frame(height: layout.rowHeight).padding(.top, layout.rowInset)
            }
            ForEach(model.peekRows, id: \.self) { id in
                if let activity = model.activity(id, in: registry) {
                    activity.view(for: .peekRow)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(height: NotchLayout.peekRow)
                        .padding(.horizontal, Space.l)
                        .contentShape(Rectangle())
                        .onTapGesture { actions.activityTapped(id) }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(Text(verbatim: activity.accessibilityLabel))
                }
            }
        }
        .foregroundStyle(theme.palette.label)
        .frame(width: shape.bodyWidth, height: shape.bottom, alignment: .top)
    }
}

#Preview("Peek · one row") {
    let (model, registry) = previewScene(.peek)
    PeekView(model: model, registry: registry, actions: NotchUIActions())
        .background(.black)
        .crannyThemeRoot(CrannyTheme())
}
