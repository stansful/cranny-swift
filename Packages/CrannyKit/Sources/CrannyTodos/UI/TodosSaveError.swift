// CrannyTodos/UI/TodosSaveError.swift — after a failed save the header turns into the error of DESIGN.md §6.8:
// a `danger` "!" + one line + retry, all visible ("! Couldn’t save your to-dos · Try again", shortened to
// "! Not saved · Try again" and "! Not saved" as the card narrows). It is one button: a click retries; so do ↩ and
// Space once ↑ from the first row has selected it (the list's focus ring then surrounds it), and VoiceOver's
// default action. The "!" with words keeps it readable without colour (§16 Differentiate Without Color).
import CrannyCore
import SwiftUI

struct TodosSaveError: View {
    @Environment(\.cranny) private var theme
    @State private var hovered = false
    let metrics: TodoMetrics
    /// The list's keyboard selection is on this line.
    let showsFocusRing: Bool
    let retry: () -> Void

    var body: some View {
        Button(action: retry) {
            ViewThatFits(in: .horizontal) {
                line(TodosStrings.saveFailed, showsRetry: true)
                line(TodosStrings.notSaved, showsRetry: true)
                line(TodosStrings.notSaved, showsRetry: false, truncates: true)     // the last resort never overflows
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .todoHitArea(CGSize(width: HitTarget.nook.width, height: metrics.headerHeight))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .animation(theme.animation(.hover), value: hovered)
        .background {
            // The same 2-pt ring as a selected row: 22 pt tall around the 16-pt line, 4 pt beyond its sides.
            Color.clear
                .crannyFocusRing(showsFocusRing, radius: theme.grid.innerRadius - Radius.focusRingOutset)
                .padding(.horizontal, Radius.focusRingOutset - Space.xs)
        }
        .help(TodosStrings.saveFailedHelp)
        .accessibilityLabel(Text(verbatim: TodosStrings.saveFailed))
        .accessibilityHint(Text(verbatim: TodosStrings.saveRetryHint))
    }

    /// One candidate for `ViewThatFits`: at its ideal width, except the last one, which truncates if it must.
    private func line(_ message: String, showsRetry: Bool, truncates: Bool = false) -> some View {
        let p = theme.palette
        // Tight (2 pt) spacing so "! Не сохранено · Повторить" still fits a 3-cell card (160 pt) in Russian.
        return HStack(alignment: .firstTextBaseline, spacing: Space.xxs) {
            Image(systemName: "exclamationmark")
                .font(.system(size: metrics.glyph, weight: TodoMetrics.symbolWeight))
                .foregroundStyle(p.danger)
            Text(message)
                .foregroundStyle(p.danger)
            if showsRetry {
                Text(verbatim: "·")
                    .foregroundStyle(p.tertiaryLabel)
                Text(TodosStrings.tryAgain)
                    .fontWeight(.semibold)
                    .foregroundStyle(hovered ? p.label : p.secondaryLabel)
            }
        }
        .crannyFont(.caption)
        .lineLimit(1)
        .fixedSize(horizontal: !truncates, vertical: false)
    }
}

#Preview("Save error") {
    VStack(alignment: .leading, spacing: Space.l) {
        ForEach([3, 2, 4], id: \.self) { cells in
            TodosSaveError(metrics: TodoMetrics(textSize: .standard), showsFocusRing: cells == 4) {}
                .frame(width: CGFloat(cells) * 64 - 32, height: 16)
        }
    }
    .padding(Space.l)
    .background(.black)
    .crannyThemeRoot(CrannyTheme())
}
