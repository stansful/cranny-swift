// CrannyTodos/UI/TodosView.swift — the widget's content (the card around it is NotchUI's): header + list, or
// one of the states of DESIGN.md §6.8 — empty ("No to-dos yet" / "All done" + New to-do), loading (nothing for
// 300 ms, then a quiet ring), error (danger glyph + one line + Try again). Stages (`isPreview`), layout editing
// and Demo redaction draw the list read-only.
import CrannyCore
import SwiftUI

struct TodosView: View {
    @Environment(\.cranny) private var theme
    let model: TodosModel
    let context: WidgetContext

    private enum Content: Equatable { case list, empty, loading, failed }

    private var isReadOnly: Bool { context.isPreview || context.isEditingLayout || context.redactsPersonalData }

    /// Stages show the user's own list, or samples when it is empty (never written).
    private var items: [Todo] {
        guard context.isPreview else { return model.visibleItems }
        let own = model.store.phase == .ready ? model.visibleItems.filter { !$0.title.isBlank } : []
        return own.isEmpty ? TodosModel.sampleTodos() : own
    }

    private var headerCount: TodoHeaderCount {
        guard context.isPreview else { return model.headerCount }
        return TodoHeaderCount(remaining: items.count(where: { !$0.isDone }), completed: items.count(where: \.isDone))
    }

    private var content: Content {
        if context.isPreview { return .list }
        switch model.store.phase {
        case .loading: return .loading
        case .failed: return .failed
        case .ready: return model.visibleItems.isEmpty ? .empty : .list
        }
    }

    var body: some View {
        let metrics = TodoMetrics(textSize: theme.textSize)
        ZStack {
            switch content {
            case .list:
                VStack(alignment: .leading, spacing: Space.xs) {
                    TodosHeader(count: headerCount,
                                showsCount: context.cells >= 3, saveFailed: model.store.saveFailed && !isReadOnly,
                                metrics: metrics, isFocusedWidget: context.isFocused) { model.store.retrySave() }
                    TodoListView(model: model, items: items, metrics: metrics,
                                 checkStyle: model.checkStyle(personality: theme.motion, reduceMotion: theme.reduceMotion),
                                 isReadOnly: isReadOnly, redacts: context.redactsPersonalData,
                                 isFocusedWidget: context.isFocused)
                }
                .transition(.opacity)
            case .empty:
                TodosEmptyView(allDone: model.completedCount > 0, isReadOnly: isReadOnly,
                               isFocusedWidget: context.isFocused) { model.beginNew(after: nil) }
                    .transition(.opacity)
            case .loading:
                TodosLoadingView(metrics: metrics)
            case .failed:
                WidgetStateView(.error, symbol: "exclamationmark", message: TodosStrings.loadFailed,
                                actionTitle: TodosStrings.tryAgain) { model.reload() }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .animation(theme.animation(.contentSwap), value: content)
    }
}

/// Empty: one line + one action (DESIGN.md §6.8). ↩ or Space starts a to-do when the widget has the keyboard.
private struct TodosEmptyView: View {
    @FocusState private var isFocused: Bool
    let allDone: Bool
    let isReadOnly: Bool
    let isFocusedWidget: Bool
    let newTodo: @MainActor () -> Void

    var body: some View {
        WidgetStateView(.empty, symbol: allDone ? "checkmark.circle.fill" : "checklist",
                        message: allDone ? TodosStrings.allDone : TodosStrings.noTodos,
                        actionTitle: isReadOnly ? nil : TodosStrings.newTodo, action: isReadOnly ? nil : newTodo)
            .focusable(!isReadOnly, interactions: .edit)
            .focused($isFocused)
            .focusEffectDisabled()
            .onKeyPress(keys: [.return, .space]) { press in
                guard press.modifiers.isEmpty, !isReadOnly else { return .ignored }
                newTodo()
                return .handled
            }
            .onChange(of: isFocusedWidget) { _, focused in if focused { isFocused = true } }
            .onAppear { if isFocusedWidget { isFocused = true } }
    }
}

/// ≤ 300 ms: nothing; longer: a quiet 2.5-pt ring (DESIGN.md §6.8). One sleep while visible, no timer.
private struct TodosLoadingView: View {
    @Environment(\.cranny) private var theme
    @State private var showsRing = false
    let metrics: TodoMetrics

    var body: some View {
        ZStack {
            if showsRing {
                ProgressRing(progress: 0.25, color: theme.palette.tertiaryLabel, lineWidth: StrokeWidth.ringCompact)
                    .frame(width: metrics.circle, height: metrics.circle)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            try? await Task.sleep(for: .milliseconds(300))
            withAnimation(theme.animation(.contentSwap)) { showsRing = true }
        }
        .accessibilityHidden(true)
    }
}

#Preview("To-dos · 3 cells") {
    let model = TodosModel.preview(TodosModel.sampleTodos(count: 4, completed: [3]))
    TodosView(model: model, context: WidgetContext(cells: 3, contentSize: CGSize(width: 160, height: 96)))
        .crannyCard(cells: 3)
        .padding(Space.l)
        .background(.black)
        .crannyThemeRoot(CrannyTheme())
}

#Preview("To-dos · 2 cells") {
    let model = TodosModel.preview()
    TodosView(model: model, context: WidgetContext(cells: 2, contentSize: CGSize(width: 96, height: 96)))
        .crannyCard(cells: 2)
        .padding(Space.l)
        .background(.black)
        .crannyThemeRoot(CrannyTheme())
}

#Preview("To-dos · empty") {
    let model = TodosModel.preview([])
    TodosView(model: model, context: WidgetContext(cells: 3, contentSize: CGSize(width: 160, height: 96)))
        .crannyCard(cells: 3)
        .padding(Space.l)
        .background(.black)
        .crannyThemeRoot(CrannyTheme())
}
