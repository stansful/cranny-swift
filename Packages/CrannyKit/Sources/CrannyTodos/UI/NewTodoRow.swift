// CrannyTodos/UI/NewTodoRow.swift — the trailing "New to-do" row: `plus` and the words in `quaternaryLabel`,
// aligned with the circles above (DESIGN.md §7.6). Click, ↩ or Space starts a new to-do at the end.
import CrannyCore
import SwiftUI

struct NewTodoRow: View {
    @Environment(\.cranny) private var theme
    @State private var hovered = false
    let metrics: TodoMetrics
    let showsFocusRing: Bool
    let action: () -> Void

    var body: some View {
        let p = theme.palette
        Button(action: action) {
            HStack(spacing: Space.m) {
                Image(systemName: "plus")
                    .font(.system(size: metrics.glyph, weight: TodoMetrics.symbolWeight))
                    .frame(width: metrics.circle, height: metrics.circle)
                Text(TodosStrings.newTodo)
                    .crannyFont(.body)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundStyle(hovered ? p.tertiaryLabel : p.quaternaryLabel)
            .frame(height: metrics.rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .animation(theme.animation(.hover), value: hovered)
        .background {
            Color.clear
                .crannyFocusRing(showsFocusRing, radius: theme.grid.innerRadius - Radius.focusRingOutset)
                .padding(.vertical, Radius.focusRingOutset)
                .padding(.horizontal, Radius.focusRingOutset - Space.xs)
        }
        .accessibilityLabel(Text(verbatim: TodosStrings.newTodo))
    }
}

#Preview("New to-do row") {
    VStack(spacing: 0) {
        NewTodoRow(metrics: TodoMetrics(textSize: .standard), showsFocusRing: false) {}
        NewTodoRow(metrics: TodoMetrics(textSize: .standard), showsFocusRing: true) {}
    }
    .crannyCard(cells: 3)
    .padding(Space.l)
    .background(.black)
    .crannyThemeRoot(CrannyTheme())
}
