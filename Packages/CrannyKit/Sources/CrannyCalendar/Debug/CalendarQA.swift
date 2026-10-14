// CrannyCalendar/Debug/CalendarQA.swift — DEBUG-only visual QA (docs/CONTRIBUTING.md "Visual QA hooks"): the
// launch argument `--qa-calendar <state>` replaces EventKit and TCC with fixtures, so the real panel can be
// screenshotted in every state without calendar access, prompts or the user's events:
//
//   --qa-calendar sample          the sample day (a meeting in progress, one in 4 minutes with Zoom, …)
//   --qa-calendar inProgress      only the meeting in progress (no "Meeting soon", so it takes the wings)
//   --qa-calendar empty           nothing left today; tomorrow's first event
//   --qa-calendar notDetermined   the "Show your events" state (the button does nothing)
//   --qa-calendar denied          access denied
//   --qa-calendar error           the error state
//
// Compiled out of Release builds.
#if DEBUG
import CrannyCore
import Foundation
import os

private let log = Log.logger(.calendar)

enum CalendarQA {
    /// The fixture source and access for the `--qa-calendar` argument, or nil without it.
    static func fixture(arguments: [String] = ProcessInfo.processInfo.arguments)
        -> (source: any EventSource, access: any CalendarAccess)? {
        guard let index = arguments.firstIndex(of: "--qa-calendar"), index + 1 < arguments.count else { return nil }
        let state = arguments[index + 1]
        let now = Date()
        let calendars = CalendarSamples.calendars
        log.info("QA: calendar fixture \(state, privacy: .public)")
        switch state {
        case "inProgress":
            let events = CalendarSamples.events(around: now).filter { $0.id != "sample.standup" }
            return (FixtureEventSource(events: events, calendars: calendars), StaticCalendarAccess(.granted))
        case "empty":
            let tomorrow = CalendarSamples.events(around: now).filter { !$0.overlaps(EventWindow.day(offset: 0, from: now, calendar: .autoupdatingCurrent)) }
            return (FixtureEventSource(events: tomorrow, calendars: calendars), StaticCalendarAccess(.granted))
        case "notDetermined":
            return (FixtureEventSource(), StaticCalendarAccess(.notDetermined))
        case "denied":
            return (FixtureEventSource(), StaticCalendarAccess(.denied))
        case "error":
            return (FixtureEventSource(calendars: calendars, failure: .unavailable), StaticCalendarAccess(.granted))
        default:
            return (FixtureEventSource(events: CalendarSamples.events(around: now), calendars: calendars), StaticCalendarAccess(.granted))
        }
    }
}
#endif
