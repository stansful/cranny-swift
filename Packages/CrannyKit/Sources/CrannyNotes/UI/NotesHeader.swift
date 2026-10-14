// CrannyNotes/UI/NotesHeader.swift — the Notes card's top row (DESIGN.md §7.5):
//   deploy.md ⌄                      </>  ⤢  +
// headline title (double-click or ⌘R to rename) · ⌄ note list · code toggle (accent when on) · focus · new (⌘N).
// Buttons draw a 24-pt well but take clicks over 28 × 24 (DESIGN.md §2.3 hit targets in the Nook).
import CrannyCore
import SwiftUI

struct NotesHeader: View {
    @Environment(\.cranny) private var theme
    let model: NotesModel
    let entry: NotesModel.Entry
    /// At 3 cells the title needs the room; focus mode stays in the ⌄ menu and on ⌘↩.
    var showsFocusButton = true

    var body: some View {
        HStack(spacing: 0) {
            if model.renamingID == entry.id {
                RenameField(model: model, title: entry.title)
            } else {
                title
            }
            NoteListMenu(model: model, entry: entry)
            Spacer(minLength: Space.xs)
            if model.saveFailed {
                // The automatic retries stop after a few minutes; a click (or the next edit) tries again.
                HeaderButton(symbol: "exclamationmark", label: NotesStrings.saveFailed, tint: theme.palette.danger) {
                    model.retrySave()
                }
                .accessibilityHint(Text(NotesStrings.tryAgain))
            }
            HeaderButton(symbol: "chevron.left.forwardslash.chevron.right", label: NotesStrings.codeMode,
                         isOn: entry.mode == .code, shortcut: KeyboardShortcut("/", modifiers: .command)) {
                model.toggleCodeMode()
            }
            if showsFocusButton {
                HeaderButton(symbol: model.isFocusPresented ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                             label: model.isFocusPresented ? NotesStrings.exitFocusMode : NotesStrings.focusMode,
                             shortcut: KeyboardShortcut(.return, modifiers: .command)) {
                    model.toggleFocusMode()
                }
            }
            HeaderButton(symbol: "plus", label: NotesStrings.newNote, shortcut: KeyboardShortcut("n", modifiers: .command)) {
                model.newNote()
            }
        }
        .frame(height: HitTarget.nook.height)
    }

    private var title: some View {
        Text(entry.title)
            .crannyFont(.headline)
            .foregroundStyle(theme.palette.label)
            .lineLimit(1)
            .truncationMode(.tail)
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { model.beginRename() }
            .help(NotesStrings.doubleClickToRename)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(NotesStrings.noteTitle))
            .accessibilityValue(Text(entry.title))
            .accessibilityAddTraits(.isHeader)
            .accessibilityAction(named: Text(NotesStrings.rename)) { model.beginRename() }
    }
}

/// A plain icon button: 24-pt well (hover/pressed fills from the theme), 28 × 24 hit area, accent glyph when on.
struct HeaderButton: View {
    @Environment(\.cranny) private var theme
    let symbol: String
    let label: String
    var isOn = false
    /// A glyph colour other than the default (`danger` for the save warning).
    var tint: Color?
    /// Works while the panel is key, also when the editor is not first responder.
    var shortcut: KeyboardShortcut?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .foregroundStyle(tint ?? (isOn ? theme.accentColor : theme.palette.secondaryLabel))
        }
        .keyboardShortcut(shortcut)
        .buttonStyle(CrannyIconButtonStyle(isOn ? .filled : .plain, size: HitTarget.nook.height))
        .frame(width: HitTarget.nook.width, height: HitTarget.nook.height)
        .contentShape(Rectangle())
        .help(label)
        .accessibilityLabel(Text(label))
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// Inline rename in place of the title: Return commits and returns to the note, Esc cancels and returns to the
/// note, a click elsewhere commits and leaves the keyboard where it went.
private struct RenameField: View {
    @Environment(\.cranny) private var theme
    @FocusState private var isFocused: Bool
    @State private var draft: String
    let model: NotesModel

    init(model: NotesModel, title: String) {
        self.model = model
        _draft = State(initialValue: title)
    }

    var body: some View {
        TextField(text: $draft, prompt: Text(NotesStrings.noteTitle)) { Text(NotesStrings.noteTitle) }
            .textFieldStyle(.plain)
            .crannyFont(.headline)
            .foregroundStyle(theme.palette.label)
            .padding(.horizontal, Space.s)
            .frame(height: HitTarget.nook.height - Space.xs)
            .background(RoundedRectangle(cornerRadius: Radius.chip, style: .continuous).fill(theme.palette.well))
            .focused($isFocused)
            .onSubmit { model.commitRename(draft, returnsFocus: true) }
            .onExitCommand { model.cancelRename() }
            .onChange(of: isFocused) { _, focused in
                if !focused && model.renamingID != nil { model.commitRename(draft) }
            }
            .task {
                try? await Task.sleep(for: .milliseconds(50))                    // after the panel became key
                isFocused = true
            }
    }
}

#Preview("Header · code note") {
    let model = NotesModel.preview()
    NotesPreviewFrame(width: 224) { NotesHeader(model: model, entry: model.entries[0]) }
}

#Preview("Header · 3 cells, save failed") {
    let model = NotesModel.preview()
    let _ = model.saveFailed = true
    NotesPreviewFrame(width: 160) { NotesHeader(model: model, entry: model.entries[1], showsFocusButton: false) }
}
