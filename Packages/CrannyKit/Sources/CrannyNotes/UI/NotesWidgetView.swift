// CrannyNotes/UI/NotesWidgetView.swift — the Notes card's content (DESIGN.md §7.5, §6.8): header + editor, the
// note list beside it at 6 cells and wider, the inline delete confirmation and the widget states (loading,
// error, empty). On stages, while editing the layout and under demo redaction it draws a static, read-only note.
import CrannyCore
import SwiftUI

struct NotesWidgetView: View {
    @Environment(\.cranny) private var theme
    @Environment(\.displayScale) private var displayScale
    let model: NotesModel
    let settings: SettingsStore
    let context: WidgetContext

    /// A real, editable widget: not a stage, not layout editing, not redacted.
    private var isLive: Bool { !context.isPreview && !context.isEditingLayout && !context.redactsPersonalData }
    /// The widget in the Nook, live or not. Only it drives the model's holds: a stage never touches them.
    private var isInNook: Bool { !context.isPreview }
    /// ≥ 6 cells (and focus mode): the note list sidebar and line numbers (DESIGN.md §6.7).
    private var isWide: Bool { context.cells >= 6 }
    /// One cell at 6–7 cells; two from 8 cells and in focus mode, where one cell would cut every title short.
    private var sidebarCells: Int { context.cells >= 8 || context.rows >= 3 ? 2 : 1 }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .onChange(of: Presentation(isLive: isLive, isFocusMode: context.rows >= 3), initial: true) { _, shown in
                if isInNook { model.widgetPresentationChanged(isLive: shown.isLive, isFocusPresented: shown.isFocusMode) }
            }
            // `initial`: the Nook mounts the widget already focused when it opens with `focus: .notes` (⌃⌥N, ⌘K).
            .onChange(of: context.isFocused, initial: true) { _, focused in
                if focused && isLive { model.requestFocus() }                     // Tab / shell focus → type at once
            }
            .onDisappear { if isInNook { model.widgetDisappeared() } }
    }

    private struct Presentation: Equatable {
        var isLive: Bool
        var isFocusMode: Bool
    }

    @ViewBuilder private var content: some View {
        if context.redactsPersonalData {
            RedactedNoteView()
        } else if !isLive {
            NotePreviewView(note: model.selectedEntry.flatMap { model.note($0.id) } ?? NotePreviewView.sample)
        } else {
            switch model.phase {
            case .idle, .loading:
                NotesLoadingView()
            case .failed:
                WidgetStateView(.error, symbol: "exclamationmark", message: NotesStrings.loadFailed,
                                actionTitle: NotesStrings.tryAgain) { model.reload() }
            case .loaded:
                if let entry = model.selectedEntry {
                    editor(entry)
                } else {
                    WidgetStateView(.empty, symbol: "note.text", message: NotesStrings.empty,
                                    actionTitle: NotesStrings.newNote) { model.newNote() }
                }
            }
        }
    }

    private func editor(_ entry: NotesModel.Entry) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            NotesHeader(model: model, entry: entry, showsFocusButton: context.cells >= 4 || context.rows >= 3)
            if model.pendingDeletion == entry.id {
                DeleteConfirmationView(model: model, title: entry.title)
                    .transition(.opacity)
            } else {
                HStack(alignment: .top, spacing: theme.grid.gutter) {
                    if isWide {
                        NoteSidebar(model: model)
                            .frame(width: theme.grid.width(cells: sidebarCells))
                        Rectangle().fill(theme.palette.hairline)
                            .frame(width: StrokeWidth.hairline(displayScale))
                            .accessibilityHidden(true)
                    }
                    textArea(entry)
                }
            }
        }
        .animation(theme.animation(.contentSwap), value: model.pendingDeletion)
    }

    private func textArea(_ entry: NotesModel.Entry) -> some View {
        let style = EditorStyle(theme: theme, mode: entry.mode)
        return NoteTextView(model: model, entry: entry, typingEffect: settings[CoreSettings.typingEffect],
                            showsLineNumbers: isWide, focusRequested: model.focusRequested,
                            externalRevision: model.externalRevision)
            .modifier(WholeLines(lineHeight: style.lineHeight))
            .overlay(alignment: .topLeading) {
                if model.emptyNotes.contains(entry.id) {
                    Text(NotesStrings.placeholder)
                        .font(style.font(for: nil))
                        .foregroundStyle(style.placeholderColor)
                        .padding(.leading, isWide && entry.mode == .code
                                 ? LineNumberRuler.thickness(digits: 1, font: LineNumberRuler.font(for: style)) : 0)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
    }
}

/// Gives the editor a whole number of lines (code lines are 16 pt in a 68-pt area): it never ends on the tops
/// of letters, and the spare points stay empty below the last line.
private struct WholeLines: ViewModifier {
    let lineHeight: CGFloat

    func body(content: Content) -> some View {
        GeometryReader { proxy in
            let lines = max((proxy.size.height / max(lineHeight, 1)).rounded(.down), 1)
            content.frame(width: proxy.size.width, height: min(lines * lineHeight, proxy.size.height), alignment: .top)
        }
    }
}

/// ≤ 300 ms: nothing; longer: a quiet ring (DESIGN.md §6.8).
private struct NotesLoadingView: View {
    @Environment(\.cranny) private var theme
    @State private var isSlow = false

    var body: some View {
        ZStack {
            if isSlow {
                ProgressRing(progress: 0.25, color: theme.palette.tertiaryLabel, lineWidth: StrokeWidth.ringCompact)
                    .frame(width: Space.xl, height: Space.xl)
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            try? await Task.sleep(for: .milliseconds(300))
            isSlow = true
        }
    }
}

// MARK: - Previews

#Preview("Notes · code, 4 cells") {
    NotesPreviewHost(cells: 4, sample: .deploy)
}

#Preview("Notes · plain, 3 cells") {
    NotesPreviewHost(cells: 3, sample: .groceries)
}

#Preview("Notes · wide with list, 6 cells") {
    NotesPreviewHost(cells: 6, sample: .deploy)
}

#Preview("Notes · empty") {
    NotesPreviewHost(cells: 4, sample: nil)
}
