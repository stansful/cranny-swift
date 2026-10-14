import Foundation
import Testing
@testable import CrannyCalendar

/// The widget's list for one day (DESIGN.md §7.2).
@Suite struct AgendaTests {
    private let cal = T.calendar()
    private var today: DateInterval { EventWindow.day(offset: 0, from: T.date(), calendar: cal) }

    private func events() -> [EventSnapshot] {
        EventFilter().apply([
            T.event("early", start: T.date(h: 8), minutes: 30),
            T.event("long", start: T.date(h: 9), minutes: 120),
            T.event("review", start: T.date(h: 9, 45), minutes: 30),
            T.event("lunch", start: T.date(h: 12), minutes: 60),
            T.event("late", start: T.date(h: 17), minutes: 30),
            T.event("holiday", start: T.date(h: 0), minutes: 1440, allDay: true),
            T.event("tomorrow", start: T.date(2026, 10, 15, h: 9)),
        ])
    }

    @Test func rolesToday() {
        let agenda = Agenda.make(events: events(), day: today, now: T.date(h: 10), isToday: true, showsPastToday: true)
        #expect(agenda.rows.map(\.id) == ["holiday", "early", "long", "review", "lunch", "late"])
        #expect(agenda.rows.map(\.role) == [.allDay, .ended, .live, .live, .upcoming, .upcoming])
        // Two meetings overlap: the one that started last is featured.
        #expect(agenda.featuredID == "review")
        #expect(!agenda.isEmptyToday)
    }

    @Test func nextEventIsFeaturedWhenNothingIsLive() {
        let agenda = Agenda.make(events: events(), day: today, now: T.date(h: 11, 30), isToday: true, showsPastToday: true)
        #expect(agenda.featuredID == "lunch")
        #expect(agenda.rows.first { $0.id == "lunch" }?.role == .next)
        #expect(agenda.rows.first { $0.id == "late" }?.role == .upcoming)
    }

    @Test func pastEventsCanBeHidden() {
        let agenda = Agenda.make(events: events(), day: today, now: T.date(h: 11, 30), isToday: true, showsPastToday: false)
        #expect(agenda.rows.map(\.id) == ["holiday", "lunch", "late"])
    }

    @Test func emptyTodayIgnoresEndedEvents() {
        let list = EventFilter().apply([T.event("early", start: T.date(h: 8)), T.event("tomorrow", start: T.date(2026, 10, 15, h: 9))])
        let agenda = Agenda.make(events: list, day: today, now: T.date(h: 18), isToday: true, showsPastToday: true)
        #expect(agenda.isEmptyToday)
        #expect(agenda.featuredID == nil)
        let tomorrow = EventWindow.day(offset: 1, from: T.date(h: 18), calendar: cal)
        #expect(Agenda.firstTimedEvent(in: list, day: tomorrow)?.id == "tomorrow")
    }

    @Test func otherDaysHaveNoFeaturedRow() {
        let tomorrow = EventWindow.day(offset: 1, from: T.date(), calendar: cal)
        let future = Agenda.make(events: events(), day: tomorrow, now: T.date(), isToday: false, showsPastToday: true)
        #expect(future.rows.map(\.id) == ["tomorrow"])
        #expect(future.rows.map(\.role) == [.upcoming])
        #expect(future.featuredID == nil)

        let yesterday = EventWindow.day(offset: -1, from: T.date(), calendar: cal)
        let past = Agenda.make(events: [T.event("old", start: T.date(2026, 10, 13, h: 9))], day: yesterday, now: T.date(),
                               isToday: false, showsPastToday: false)
        #expect(past.rows.map(\.role) == [.ended])                         // never hidden on earlier days
    }

    @Test func longBlocksAreListedButNotFeatured() {
        let list = EventFilter().apply([T.event("conference", start: T.date(2026, 10, 13, h: 9), minutes: 3 * 24 * 60),
                                        T.event("call", start: T.date(h: 15))])
        let agenda = Agenda.make(events: list, day: today, now: T.date(), isToday: true, showsPastToday: true)
        #expect(agenda.rows.map(\.id) == ["conference", "call"])
        #expect(agenda.featuredID == "call")
    }

    @Test func multiDayEventsAppearOnEveryDay() {
        let trip = T.event("trip", start: T.date(2026, 10, 13, h: 18), minutes: 48 * 60)
        for offset in [0, 1] {
            let day = EventWindow.day(offset: offset, from: T.date(), calendar: cal)
            #expect(Agenda.make(events: [trip], day: day, now: T.date(), isToday: offset == 0, showsPastToday: true).rows.count == 1)
        }
    }
}
