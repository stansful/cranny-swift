// CrannyNotes/NotesSettings.swift — the module's settings keys (ARCHITECTURE.md §10.6). Content (the notes
// themselves) is not settings: it lives in `AppPaths/notes/` and survives "Reset All Settings".
import CrannyCore

/// How a note is edited: prose in SF Pro, or code in SF Mono with syntax colours (DESIGN.md §7.5).
public nonisolated enum NoteMode: String, Codable, CaseIterable, Sendable {
    /// Prose: SF Pro 13, no colours.
    case plain
    /// Code: SF Mono 12, syntax colours for Markdown and common languages.
    case code
}

/// Settings of the Notes module (namespace `notes`). The typing effect is `CoreSettings.typingEffect`
/// (Appearance), shared with the widget's options popover.
public enum NotesSettings {
    /// The mode of new notes (Layout & Widgets ▸ Notes options).
    public static let defaultMode = SettingKey<NoteMode>(.notes, "defaultMode", default: .plain)
    /// The note shown when the widget appears (a note's UUID); nil = the first note.
    public static let lastNoteID = SettingKey<String?>(.notes, "lastNoteID", default: nil)
}
