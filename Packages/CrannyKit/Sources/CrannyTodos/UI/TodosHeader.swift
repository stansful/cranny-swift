// CrannyTodos/UI/TodosHeader.swift — "To-dos" (`eyebrow`) + "3 left" (`caption`, tertiary) (DESIGN.md §7.6).
// At 2 cells the count is left out (§6.7). While ⌘ is held and the widget has the keyboard, the count makes
// room for the widget's key caps (§6.5). After a failed save a `danger` "!" sits before the count; clicking it
// retries (it is also the only place the failure shows, with a tooltip and a VoiceOver label).
import CrannyCore
import SwiftUI

struct TodosHeader: View {
    @Environment(\.cranny) private var theme
    @Environment(\.notchContext) private var notchContext
    let remaining: Int
    let showsCount: Bool
    let saveFailed: Bool
    let metrics: TodoMetrics
    /// The widget has the keyboard: hold-⌘ hints may show.
    var isFocusedWidget = false
    let retrySave: () -> Void

    var body: some View {
        let p = theme.palette
        HStack(alignment: .firstTextBaseline, spacing: Space.s) {
            Text(TodosStrings.title)
                .crannyFont(.eyebrow)
                .foregroundStyle(p.secondaryLabel)
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: Space.xs)
            if saveFailed {
                Button(action: retrySave) {
                    Image(systemName: "exclamationmark")
                        .font(.system(size: metrics.plusGlyph, weight: .bold))
                        .foregroundStyle(p.danger)
                        .frame(width: metrics.circle, height: metrics.headerHeight)
                        .todoHitArea(CGSize(width: metrics.circle, height: metrics.headerHeight))
                }
                .buttonStyle(.plain)
                .help(TodosStrings.saveFailed)
                .accessibilityLabel(Text(verbatim: TodosStrings.saveFailed))
            }
            if showsCount && notchContext.showsCommandHints && isFocusedWidget {
                HStack(spacing: Space.xxs) {
                    KeyCap("↩")
                    KeyCap("␣")
                    KeyCap("⌘↑↓")
                }
                .transition(.opacity)
            } else if showsCount {
                Text(remaining == 0 ? TodosStrings.allDone : TodosStrings.remaining(remaining))
                    .crannyFont(.caption)
                    .foregroundStyle(p.tertiaryLabel)
                    .lineLimit(1)
                    .contentTransition(theme.reduceMotion ? .opacity : .numericText(value: Double(remaining)))
                    .animation(theme.animation(.contentSwap), value: remaining)
            }
        }
        .frame(height: metrics.headerHeight)
        .animation(theme.animation(.hover), value: notchContext.showsCommandHints)
    }
}

#Preview("Header") {
    VStack(spacing: Space.l) {
        TodosHeader(remaining: 3, showsCount: true, saveFailed: false, metrics: TodoMetrics(textSize: .standard)) {}
        TodosHeader(remaining: 0, showsCount: true, saveFailed: true, metrics: TodoMetrics(textSize: .standard)) {}
        TodosHeader(remaining: 3, showsCount: false, saveFailed: false, metrics: TodoMetrics(textSize: .standard)) {}
    }
    .frame(width: 160)
    .padding(Space.l)
    .background(.black)
    .crannyThemeRoot(CrannyTheme())
}
