// CrannyCalendar/CalendarError.swift — failures a user can see (ARCHITECTURE.md §9.3). Missing access and an
// empty day are states, not errors.
import Foundation

nonisolated enum CalendarError: Error, LocalizedError, Equatable, Sendable {
    /// Reading events failed (the calendar database was unavailable).
    case unavailable

    var errorDescription: String? {
        switch self {
        case .unavailable:
            String(localized: "Couldn't read your calendars", bundle: .module, comment: "Calendar widget: error state, one line")
        }
    }
}
