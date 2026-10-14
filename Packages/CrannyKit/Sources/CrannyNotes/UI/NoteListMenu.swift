// CrannyNotes/UI/NoteListMenu.swift — the ⌄ menu beside the title (DESIGN.md §7.5): every note (the current one
// checked), New, Rename, Delete (asks first), previous/next, and the note's mode and code language. A native
// menu: while it tracks, the shell holds the panel open (ARCHITECTURE.md §4.5).
import CrannyCore
import SwiftUI

struct NoteListMenu: View {
    @Environment(\.cranny) private var theme
    let model: NotesModel
    let entry: NotesModel.Entry

    var body: some View {
        Menu {
            Picker(selection: Binding(get: { model.selectedID }, set: { if let id = $0 { model.select(id) } })) {
                ForEach(model.entries) { note in
                    Text(note.title).tag(Optional(note.id))
                }
            } label: {
                Text(NotesStrings.allNotes)
            }
            .pickerStyle(.inline)
            Divider()
            Button(NotesStrings.newNote) { model.newNote() }
            Button(NotesStrings.rename) { model.beginRename() }
            if model.entries.count > 1 {
                Button(NotesStrings.previousNote) { model.selectNext(false) }
                Button(NotesStrings.nextNote) { model.selectNext(true) }
            }
            Divider()
            modeSection
            Divider()
            Button(NotesStrings.deleteEllipsis, role: .destructive) { model.requestDelete() }
        } label: {
            Image(systemName: "chevron.down")
                .crannyFont(.caption)
                .foregroundStyle(theme.palette.tertiaryLabel)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .frame(width: HitTarget.nook.width, height: HitTarget.nook.height)
        .contentShape(Rectangle())
        .help(NotesStrings.allNotes)
        .accessibilityLabel(Text(NotesStrings.allNotes))
    }

    @ViewBuilder private var modeSection: some View {
        Picker(selection: Binding(get: { entry.mode }, set: { model.setMode($0, for: entry.id) })) {
            Text(NotesStrings.plainText).tag(NoteMode.plain)
            Text(NotesStrings.code).tag(NoteMode.code)
        } label: {
            Text(NotesStrings.mode)
        }
        .pickerStyle(.inline)
        if entry.mode == .code {
            Picker(selection: Binding(get: { entry.language }, set: { model.setLanguage($0, for: entry.id) })) {
                Text(automaticTitle).tag(CodeLanguage?.none)
                Divider()
                ForEach(CodeLanguage.allCases) { language in
                    Text(verbatim: language.displayName).tag(Optional(language))
                }
            } label: {
                Text(NotesStrings.language)
            }
            .pickerStyle(.menu)
        }
    }

    /// "Automatic (Swift)" when detection found something, else "Automatic".
    private var automaticTitle: String {
        guard let note = model.note(entry.id),
              let detected = LanguageDetector.detect(title: note.title, text: note.text) else { return NotesStrings.automatic }
        return NotesStrings.automatic(detected.displayName)
    }
}
