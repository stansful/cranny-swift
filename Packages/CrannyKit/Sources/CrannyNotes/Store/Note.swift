// CrannyNotes/Store/Note.swift — a note and the on-disk index that lists them (ARCHITECTURE.md §10.6):
// `AppPaths/notes/index.json` holds titles, modes and order; each note's text is `<uuid>.md` next to it.
import Foundation

/// One note: metadata plus its text.
nonisolated struct Note: Identifiable, Equatable, Sendable {
    var id: UUID
    var title: String
    var text: String
    var mode: NoteMode
    /// nil = Automatic (`LanguageDetector`).
    var language: CodeLanguage?
    var createdAt: Date
    var modifiedAt: Date

    init(id: UUID = UUID(), title: String, text: String = "", mode: NoteMode, language: CodeLanguage? = nil,
         createdAt: Date = Date(), modifiedAt: Date? = nil) {
        self.id = id; self.title = title; self.text = text; self.mode = mode; self.language = language
        self.createdAt = createdAt; self.modifiedAt = modifiedAt ?? createdAt
    }

    var entry: NotesIndex.Entry {
        NotesIndex.Entry(id: id, title: title, mode: mode, language: language, createdAt: createdAt, modifiedAt: modifiedAt)
    }
}

/// `index.json`: the notes in display order (newest first) without their text.
nonisolated struct NotesIndex: Codable, Equatable, Sendable {
    static let currentVersion = 1

    nonisolated struct Entry: Codable, Equatable, Sendable {
        var id: UUID
        var title: String
        var mode: NoteMode
        var language: CodeLanguage?
        var createdAt: Date
        var modifiedAt: Date

        init(id: UUID, title: String, mode: NoteMode, language: CodeLanguage?, createdAt: Date, modifiedAt: Date) {
            self.id = id; self.title = title; self.mode = mode; self.language = language
            self.createdAt = createdAt; self.modifiedAt = modifiedAt
        }

        /// Lenient: a mode or language written by a newer version falls back instead of failing the whole index.
        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(UUID.self, forKey: .id)
            title = (try? c.decode(String.self, forKey: .title)) ?? ""
            mode = (try? c.decode(NoteMode.self, forKey: .mode)) ?? .plain
            language = try? c.decodeIfPresent(CodeLanguage.self, forKey: .language)
            createdAt = (try? c.decode(Date.self, forKey: .createdAt)) ?? Date()
            modifiedAt = (try? c.decode(Date.self, forKey: .modifiedAt)) ?? createdAt
        }
    }

    var version: Int
    var notes: [Entry]

    init(version: Int = Self.currentVersion, notes: [Entry]) { self.version = version; self.notes = notes }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = (try? c.decode(Int.self, forKey: .version)) ?? Self.currentVersion
        notes = try c.decode([Entry].self, forKey: .notes)
    }
}
