// CrannyCalendar/Store/EventSource.swift — the seams the store is built on, so every piece of logic runs in
// tests without EventKit, TCC or the wall clock: where events come from (`EventSource`), whether Cranny may
// read them (`CalendarAccess`) and what time it is (`CalendarClock`).
import CrannyCore
import Foundation

/// Where events come from: EventKit in the app (`EventKitSource`), fixtures in tests, previews and visual QA.
/// Implementations do their work off the main actor and return plain values.
nonisolated protocol EventSource: Sendable {
    /// Every event calendar, for Settings ▸ Calendar ▸ Calendars.
    func calendars() async throws -> [CalendarInfo]
    /// Every occurrence overlapping `interval`, unfiltered (cancelled and declined ones included).
    func events(in interval: DateInterval) async throws -> [EventSnapshot]
    /// Drops cached state (EventKit: a new `EKEventStore` after access was granted).
    func reset() async
}

/// Whether Cranny may read events. The app's implementation is `PermissionsCenter` (the only code that touches
/// TCC, ARCHITECTURE.md §3.12); tests use a double that never prompts.
@MainActor protocol CalendarAccess: AnyObject {
    /// Observable: changes re-render the widget and reload the store.
    var status: PermissionStatus { get }
    /// Shows the system prompt. Only from the widget's "Show your events" button (ARCHITECTURE.md §7.4), never at
    /// launch or from Settings.
    func request() async -> PermissionStatus
    /// Re-reads the status (cheap; never prompts): the user may have changed it in System Settings.
    func refresh()
    /// System Settings ▸ Privacy & Security ▸ Calendars.
    func openSystemSettings()
}

/// `PermissionsCenter` behind `CalendarAccess`.
@MainActor final class PermissionsCalendarAccess: CalendarAccess {
    private let permissions: PermissionsCenter
    init(permissions: PermissionsCenter) { self.permissions = permissions }
    var status: PermissionStatus { permissions.status(.calendar) }
    func request() async -> PermissionStatus { await permissions.request(.calendar) }
    func refresh() { permissions.refresh() }
    func openSystemSettings() { permissions.openSystemSettings(.calendar) }
}

/// The current time and calendar. `live` follows the system time zone (`Calendar.autoupdatingCurrent`).
nonisolated struct CalendarClock: Sendable {
    var now: @Sendable () -> Date
    var calendar: @Sendable () -> Calendar

    static let live = CalendarClock(now: { Date() }, calendar: { Calendar.autoupdatingCurrent })

    /// A clock frozen at `date` (tests, samples).
    static func fixed(_ date: Date, calendar: Calendar = .autoupdatingCurrent) -> CalendarClock {
        CalendarClock(now: { date }, calendar: { calendar })
    }
}
