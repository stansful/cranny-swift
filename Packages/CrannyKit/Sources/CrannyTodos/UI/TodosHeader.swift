// CrannyTodos/UI/TodosHeader.swift — "To-dos" (`eyebrow`) + "3 left" (`caption`, tertiary) (DESIGN.md §7.6);
// "All done" only once something is checked, nothing while the first to-do is still a blank draft. At 2 cells
// the count is left out (§6.7). While ⌘ is held and the widget has the keyboard, the count makes room for the
// widget's key caps (§6.5). After a failed save the whole header becomes the save error (`TodosSaveError`).
import CrannyCore
import SwiftUI

struct TodosHeader: View {
    @Environment(\.cranny) private var theme
    @Environment(\.notchShowsCommandHints) private var showsCommandHints
    let count: TodoHeaderCount
    let showsCount: Bool
    let saveFailed: Bool
    let metrics: TodoMetrics
    /// The widget has the keyboard: hold-⌘ hints may show.
    var isFocusedWidget = false
    /// The list's keyboard selection is on the save error.
    var showsSaveErrorRing = false
    let retrySave: () -> Void

    var body: some View {
        Group {
            if saveFailed {
                TodosSaveError(metrics: metrics, showsFocusRing: showsSaveErrorRing, retry: retrySave)
                    .transition(.opacity)
            } else {
                titleAndCount
            }
        }
        .frame(height: metrics.headerHeight)
        .animation(theme.animation(.contentSwap), value: saveFailed)
    }

    private var titleAndCount: some View {
        let p = theme.palette
        return HStack(alignment: .firstTextBaseline, spacing: Space.s) {
            Text(TodosStrings.title)
                .crannyFont(.eyebrow)
                .foregroundStyle(p.secondaryLabel)
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: Space.xs)
            if showsCount && showsCommandHints && isFocusedWidget {
                HStack(spacing: Space.xxs) {
                    KeyCap("↩")
                    KeyCap("␣")
                    KeyCap("⌘↑↓")
                }
                .transition(.opacity)
            } else if showsCount, let text = count.text {
                Text(text)
                    .crannyFont(.caption)
                    .foregroundStyle(p.tertiaryLabel)
                    .lineLimit(1)
                    .contentTransition(theme.reduceMotion ? .opacity : .numericText(value: Double(count.value)))
                    .animation(theme.animation(.contentSwap), value: count)
            }
        }
        .animation(theme.animation(.hover), value: showsCommandHints)
    }
}

#Preview("Header") {
    VStack(spacing: Space.l) {
        TodosHeader(count: .remaining(3), showsCount: true, saveFailed: false, metrics: TodoMetrics(textSize: .standard)) {}
        TodosHeader(count: .allDone, showsCount: true, saveFailed: true, metrics: TodoMetrics(textSize: .standard)) {}
        TodosHeader(count: .remaining(3), showsCount: false, saveFailed: false, metrics: TodoMetrics(textSize: .standard)) {}
    }
    .frame(width: 160)
    .padding(Space.l)
    .background(.black)
    .crannyThemeRoot(CrannyTheme())
}
