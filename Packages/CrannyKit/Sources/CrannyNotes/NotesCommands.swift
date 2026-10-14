// CrannyNotes/NotesCommands.swift — ⌘K: "New note" and "Open ‹title›" for every note (DESIGN.md §6.4).
// Offered only while the Notes widget is on a page, because both show the note there. In-memory filtering only:
// the palette queries on every keystroke, so a command is built only for the notes that match.
import CrannyCore
import Foundation

final class NotesCommands: PaletteCommandProvider {
    private let model: NotesModel
    private let redactsTitles: @MainActor () -> Bool

    /// `redactsTitles`: demo mode with redaction on; note titles are personal and stay out of the palette.
    init(model: NotesModel, redactsTitles: @escaping @MainActor () -> Bool = { false }) {
        self.model = model
        self.redactsTitles = redactsTitles
    }

    /// "New note", then "Open ‹title›" per note in list order: those whose title or keyword contains the query (all
    /// of them for an empty query).
    func commands(matching query: String) -> [PaletteCommand] {
        guard model.notesPage != nil else { return [] }
        let needle = query.trimmingCharacters(in: .whitespaces)
        func matches(_ title: String, _ keyword: String) -> Bool {
            needle.isEmpty || title.localizedCaseInsensitiveContains(needle) || keyword.localizedCaseInsensitiveContains(needle)
        }
        let kind = NotesStrings.notes
        var result: [PaletteCommand] = []
        let newNote = NotesStrings.newNote
        if matches(newNote, kind) {
            result.append(PaletteCommand(id: "notes.new", title: newNote, kind: kind, symbol: "plus",
                                         keywords: [kind]) { [model] in model.createAndReveal() })
        }
        let entries = redactsTitles() ? [] : model.entries
        for entry in entries {
            let title = NotesStrings.open(entry.title)
            guard matches(title, entry.title) else { continue }
            let id = entry.id
            result.append(PaletteCommand(id: CommandID("notes.open.\(id.uuidString)"), title: title,
                                         kind: kind, symbol: "note.text", keywords: [entry.title]) { [model] in model.open(id) })
        }
        return result
    }
}
