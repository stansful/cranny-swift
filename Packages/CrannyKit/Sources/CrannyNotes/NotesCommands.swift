// CrannyNotes/NotesCommands.swift — ⌘K: "New note" and "Open ‹title›" for every note (DESIGN.md §6.4).
// In-memory filtering only: the palette queries on every keystroke.
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

    func commands(matching query: String) -> [PaletteCommand] {
        let kind = NotesStrings.notes
        var result = [PaletteCommand(id: "notes.new", title: NotesStrings.newNote, kind: kind, symbol: "plus",
                                     keywords: [kind]) { [model] in model.createAndReveal() }]
        let entries = redactsTitles() ? [] : model.entries
        for entry in entries {
            let id = entry.id
            result.append(PaletteCommand(id: CommandID("notes.open.\(id.uuidString)"), title: NotesStrings.open(entry.title),
                                         kind: kind, symbol: "note.text", keywords: [entry.title]) { [model] in model.open(id) })
        }
        let needle = query.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return result }
        return result.filter { command in
            command.title.localizedCaseInsensitiveContains(needle)
                || command.keywords.contains { $0.localizedCaseInsensitiveContains(needle) }
        }
    }
}
