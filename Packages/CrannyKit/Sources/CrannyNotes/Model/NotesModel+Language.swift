// CrannyNotes/Model/NotesModel+Language.swift — the "Automatic" language of code notes (DESIGN.md §7.5). Each entry
// carries what detection found, so the editor and the ⌄ menu never detect themselves; while a code note changes,
// detection runs again at most every 0.4 s (`languageDetection`), never on the keystroke path, and an entry
// changes only when the result does.
import Foundation

extension NotesModel {
    /// Seconds between two detections while a code note changes (the colours follow within this time).
    static let detectionDelay: Duration = .milliseconds(400)

    /// Runs "Automatic" again for the notes that changed; an entry changes only when its result does, and the
    /// editor then restyles the note once.
    func detectLanguages() {
        let ids = undetectedNotes
        undetectedNotes.removeAll()
        for id in ids {
            guard let note = documents[id] else { continue }
            setDetectedLanguage(Self.detectedLanguage(of: note), of: id)
        }
    }

    static func detectedLanguage(of note: Note) -> CodeLanguage? {
        note.mode == .code ? LanguageDetector.detect(title: note.title, text: note.text) : nil
    }
}
