// CrannyNotes/NotesError.swift — what the Notes widget can tell the user went wrong (ARCHITECTURE.md §9.3).
import Foundation

/// Failures the widget shows as one localized line; the underlying error goes to the log only.
nonisolated enum NotesError: Error, LocalizedError, Equatable {
    /// The notes folder could not be read (the widget shows the error state with "Try again").
    case loadFailed
    /// A save failed; the model keeps the text in memory and retries.
    case saveFailed

    var errorDescription: String? {
        switch self {
        case .loadFailed: NotesStrings.loadFailed
        case .saveFailed: NotesStrings.saveFailed
        }
    }
}
