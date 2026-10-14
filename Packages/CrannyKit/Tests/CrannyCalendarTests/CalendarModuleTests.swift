import CrannyCore
import Foundation
import SwiftUI
import Testing
@testable import CrannyCalendar

@Test func registersWithoutSideEffects() throws {
    let registry = ModuleRegistry(services: .preview())
    registry.register(CalendarModule.self)
    #expect(CalendarModule.id == .calendar)
    #expect(registry.registeringModule == nil)
    let notch = try #require(registry.services.notch as? PreviewNotchControl)
    #expect(notch.calls.isEmpty)                      // registering never opens, flashes or peeks
}

@Suite @MainActor struct CalendarModuleTests {
    @Test func contributesEverythingTheArchitectureLists() throws {
        let registry = ModuleRegistry(services: .preview())
        registry.register(CalendarModule.self)

        let widget = try #require(registry.widget(.calendar))
        #expect(widget.sizes == WidgetSizes(minimum: 2, preferred: 3, maximum: 5))
        #expect(widget.symbol == "calendar")
        #expect(widget.hasOptions)
        #expect(!widget.title.isEmpty && !widget.summary.isEmpty)

        let soon = try #require(registry.activity(.meetingSoon))
        #expect(soon.kind.defaultPriority == .alert)
        #expect(soon.kind.module == .calendar)
        #expect(soon.makeSample != nil && soon.makeOptions != nil)
        let now = try #require(registry.activity(.meetingNow))
        #expect(now.kind.defaultPriority == .ongoing)
        #expect(now.kind.canPeekOnChange)
        #expect(now.makeSample != nil && now.makeOptions != nil)

        let page = try #require(registry.settingsPages.first { $0.id == .calendar })
        #expect(page.group == .features && page.tint == .red && page.symbol == "calendar")
        #expect(page.namespaces == [.calendar])
        #expect(page.keywords.contains("Zoom"))
        #expect(registry.permissionUses.map(\.kind) == [.calendar])
        #expect(registry.permissionUses.first?.module == .calendar)
        #expect(registry.commandProviders.count == 1)
    }

    @Test func registeringTouchesNoCalendarAndAsksForNothing() {
        let services = CrannyServices.preview()
        let before = services.permissions.status(.calendar)
        let registry = ModuleRegistry(services: services)
        registry.register(CalendarModule.self)
        #expect(services.permissions.status(.calendar) == before)
        let model = CalendarModule.makeModel(services: services)
        #expect(!model.store.isStarted)                          // EventKit is read only after onLaunch
        #expect(model.scheduler.nextWake == nil)
    }

    @Test func settingsDefaultsMatchTheArchitecture() {
        #expect(CalendarSettings.daysBehind.defaultValue == 0)
        #expect(CalendarSettings.daysAhead.defaultValue == 1)
        #expect(CalendarSettings.showsPastEventsToday.defaultValue)
        #expect(CalendarSettings.hiddenCalendarIDs.defaultValue.isEmpty)
        #expect(CalendarSettings.includesAllDay.defaultValue)
        #expect(!CalendarSettings.includesBirthdays.defaultValue)
        #expect(CalendarSettings.leadMinutes.defaultValue == 5)
        #expect(CalendarSettings.inEventDisplay.defaultValue == .remaining)
        #expect(CalendarSettings.joinProviders.defaultValue == MeetingService.allCases)
        #expect(CalendarSettings.joinsInApp.defaultValue)
        #expect(CalendarSettings.leadMinutes.id == "calendar.leadMinutes")
    }

    @Test func commandsJoinTheNextMeetingAndShowTheWidget() async throws {
        let services = CrannyServices.preview()
        let notch = try #require(services.notch as? PreviewNotchControl)
        let model = CalendarModel.sample(services: services)
        let commands = CalendarCommands(model: model, notch: notch)
        let all = commands.commands(matching: "")
        #expect(all.map(\.id.rawValue) == ["calendar.joinNext", "calendar.showToday"])
        #expect(commands.commands(matching: "zoom").map(\.id.rawValue) == ["calendar.joinNext"])
        #expect(commands.commands(matching: "nothing like this").isEmpty)
        try #require(all.last).perform()
        #expect(notch.calls == ["open(nook,calendar.agenda,keyboard)"])
        services.settings[CalendarSettings.joinProviders] = []
        #expect(commands.commands(matching: "").map(\.id.rawValue) == ["calendar.showToday"])
    }

    @Test func dayPagingStaysInTheWindow() {
        let services = CrannyServices.preview()
        let model = CalendarModel.sample(services: services)
        #expect(model.dayRange == 0...1)
        model.selectDay(5)
        #expect(model.selectedOffset == 1)
        model.selectDay(-3)
        #expect(model.selectedOffset == 0)
        services.settings[CalendarSettings.daysBehind] = 2
        model.selectDay(-3)
        #expect(model.selectedOffset == -2)
        services.settings[CalendarSettings.daysBehind] = 0             // the window shrank under the selection
        #expect(model.selectedOffset == 0)
    }

    @Test func formattingPhrases() {
        #expect(CalendarFormat.duration(minutes: 0).isEmpty == false)
        #expect(MinuteMath.minutesUntil(T.date(h: 10), from: T.date(h: 9, 55, s: 50)) == 5)
        #expect(MinuteMath.minutesUntil(T.date(h: 10), from: T.date(h: 9, 59, s: 1)) == 1)
        #expect(MinuteMath.minutesUntil(T.date(h: 10), from: T.date(h: 10, 0, s: 1)) == 0)
        #expect(MinuteMath.minutesSince(T.date(h: 10), to: T.date(h: 10, 12, s: 59)) == 12)
        #expect(MinuteMath.progress(start: T.date(h: 10), end: T.date(h: 11), now: T.date(h: 10, 15)) == 0.25)
        #expect(MinuteMath.progress(start: T.date(h: 10), end: T.date(h: 10), now: T.date(h: 11)) == 1)
        // The minute clock wakes exactly when the minute count changes.
        let anchor = T.date(h: 10)
        #expect(MinuteClock<EmptyViewProbe>.nextTick(after: T.date(h: 9, 55, s: 30), anchor: anchor)
                == T.date(h: 9, 56).addingTimeInterval(0.02))
        #expect(MinuteClock<EmptyViewProbe>.nextTick(after: T.date(h: 10, 3, s: 10), anchor: anchor)
                == T.date(h: 10, 4).addingTimeInterval(0.02))
    }
}

/// A concrete `View` for naming `MinuteClock`'s static helper.
struct EmptyViewProbe: View { var body: some View { EmptyView() } }
