import CrannyCore
import Foundation
import Testing
@testable import CrannyCalendar

/// The activities as the shell sees them: active, priority (P1 → P2), revision, actions, redaction and samples.
@Suite @MainActor struct MeetingActivityTests {
    private let time = TestTime(T.date(h: 9, 55))
    private let opener = RecordingOpener()

    private func model(_ events: [EventSnapshot], services: CrannyServices = .preview()) async -> CalendarModel {
        let store = CalendarStore(source: FixtureEventSource(events: events), access: FakeAccess(.granted),
                                  settings: services.settings, clock: time.clock, center: NotificationCenter(),
                                  workspaceCenter: NotificationCenter())
        await store.reload()
        let scheduler = MeetingScheduler(events: { store.events }, leadMinutes: { services.settings[CalendarSettings.leadMinutes] },
                                         clock: time.clock, sleep: { _ in try await Task.sleep(for: .seconds(3600)) })
        scheduler.replan()
        let launcher = JoinLauncher(opener: opener, joinsInApp: { services.settings[CalendarSettings.joinsInApp] })
        return CalendarModel(store: store, scheduler: scheduler, launcher: launcher, settings: services.settings,
                             environment: services.environment, app: services.app, opener: opener)
    }

    private let standup = T.event("standup", start: T.date(h: 10), minutes: 30, title: "Standup", link: "https://zoom.us/j/42?pwd=x")

    @Test func meetingSoonIsAnAlertThenSettles() async {
        let m = await model([standup])
        let soon = MeetingSoonActivity(model: m)
        #expect(soon.isActive)
        #expect(soon.priority == .alert)
        #expect(soon.revision == 1)
        #expect(soon.slot == .medium)
        #expect(soon.opensWidget == .calendar)
        #expect(soon.palette == .tinted(standup.color))
        #expect(soon.accessibilityLabel.contains("Standup"))
        #expect(soon.accessibilityValue?.isEmpty == false)

        time.now = T.date(h: 9, 56)
        m.scheduler.replan()
        #expect(soon.priority == .ongoing)                        // P2 after the alert
        #expect(soon.revision == 1)
        time.now = T.date(h: 9, 59)
        m.scheduler.replan()
        #expect(soon.priority == .alert)                          // the one-minute alert
        #expect(soon.revision == 2)
    }

    @Test func meetingSoonThatAppearsLateIsStillAnAlert() async {
        // Lid opened 3 minutes before the meeting (lead 5): P1 for a minute from now, so the shell auto-peeks and
        // announces it (a revision change peeks only for `.alert`; the kind does not peek on change).
        time.now = T.date(h: 9, 57)
        let m = await model([standup])
        let soon = MeetingSoonActivity(model: m)
        #expect(!MeetingSoonActivity.kind().canPeekOnChange)
        #expect(soon.isActive)
        #expect(soon.revision == 1)
        #expect(soon.priority == .alert)
        time.now = T.date(h: 9, 58)
        m.scheduler.replan()
        #expect(soon.priority == .ongoing)
    }

    @Test func dismissHidesUntilTheNextMeaningfulChange() async {
        let m = await model([standup])
        let soon = MeetingSoonActivity(model: m)
        soon.dismiss()
        #expect(!soon.isActive)
        time.now = T.date(h: 9, 57)
        m.scheduler.replan()
        #expect(!soon.isActive)
        time.now = T.date(h: 9, 59, s: 30)
        m.scheduler.replan()
        #expect(soon.isActive)                                    // the last minute un-dismisses it
        #expect(soon.actions.map(\.id) == ["join", "open", "dismiss"])
    }

    @Test func meetingInProgress() async {
        time.now = T.date(h: 10, 12)
        let services = CrannyServices.preview()
        let m = await model([standup], services: services)
        let now = MeetingNowActivity(model: m)
        let soon = MeetingSoonActivity(model: m)
        #expect(now.isActive && !soon.isActive)
        #expect(now.priority == .ongoing)
        #expect(now.revision == 1)
        #expect(now.accessibilityValue == CalendarFormat.spokenTimeLeft(minutes: 18))
        services.settings[CalendarSettings.inEventDisplay] = .elapsed
        #expect(now.accessibilityValue == CalendarFormat.spokenElapsed(minutes: 12))
        #expect(now.actions.map(\.id) == ["join", "open"])
    }

    @Test func joinActionOpensTheLinkAndRespectsProviders() async throws {
        let services = CrannyServices.preview()
        let m = await model([standup], services: services)
        let soon = MeetingSoonActivity(model: m)
        opener.installedSchemes = ["zoommtg"]
        try #require(soon.actions.first { $0.id == "join" }).perform()
        #expect(opener.opened.last?.scheme == "zoommtg")

        services.settings[CalendarSettings.joinProviders] = [.teams]
        #expect(!soon.actions.contains { $0.id == "join" })
        #expect(m.nextJoinable == nil)
    }

    @Test func redactionHidesTitles() async {
        let environment = PreviewSystemEnvironment()
        let services = CrannyServices.preview(environment: environment)
        let m = await model([standup], services: services)
        let soon = MeetingSoonActivity(model: m)
        environment.isDemoMode = true
        #expect(!soon.accessibilityLabel.contains("Standup"))
        #expect(soon.middleLabel == CalendarFormat.title(standup, redacted: true))
        services.settings[CoreSettings.demoRedactsCalendar] = false
        #expect(soon.accessibilityLabel.contains("Standup"))
    }

    @Test func samplesAreSelfContained() {
        let services = CrannyServices.preview()
        for lead in [1, 3, 5, 30] {
            services.settings[CalendarSettings.leadMinutes] = lead
            let soon = MeetingSoonActivity(model: .sample(services: services))
            #expect(soon.isActive, "lead \(lead)")
            // The Settings "Simulate" chip and onboarding show the alert form, whatever the lead time.
            #expect(soon.priority == .alert, "lead \(lead)")
            #expect(soon.model.isSample)
            #expect(soon.model.scheduler.nextWake == nil)
        }
        let now = MeetingNowActivity(model: .sample(services: services))
        #expect(now.isActive)
        // Samples never open anything.
        now.model.join(now.event ?? standup)
        now.model.openInCalendar(now.event)
        #expect(opener.opened.isEmpty)
    }

    @Test func openInCalendarUsesTheEventLinkThenTheApp() async {
        let m = await model([standup])
        var event = standup
        event.eventIdentifier = "ABC:123"
        m.openInCalendar(event)
        #expect(opener.opened.last?.absoluteString == "ical://ekevent/ABC:123?method=show&options=more")
        opener.opens = false
        m.openInCalendar(event)
        #expect(opener.launchedApps == ["com.apple.iCal"])
    }
}
