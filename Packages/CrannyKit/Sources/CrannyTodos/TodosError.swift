// CrannyTodos/TodosError.swift — the failures a user can see (ARCHITECTURE.md §9.3). A missing or corrupt
// file is not an error: the list starts empty (the corrupt file is kept aside).
import Foundation

nonisolated enum TodosError: Error, LocalizedError, Equatable {
    /// `todos.json` exists but could not be read. Saving is off until a retry succeeds.
    case loadFailed
    /// The last save failed (disk full, permissions). The next edit or a retry tries again.
    case saveFailed

    var errorDescription: String? {
        switch self {
        case .loadFailed: TodosStrings.loadFailed
        case .saveFailed: TodosStrings.saveFailed
        }
    }
}
