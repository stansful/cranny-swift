// The Now Playing activity: activity rules of DESIGN.md §9.2 (P2/P3, hidden after N s paused, auto-unhide,
// revision = new tracks, swipes → previous/next with Invert), with scripted providers and a manual clock.
import CrannyCore
import Foundation
import Testing
@testable import CrannyMedia

@Suite("Now Playing activity") @MainActor struct NowPlayingActivityTests {
    private func running(_ services: CrannyServices = .preview()) async -> (MediaService, ScriptedProvider, ManualClock, NowPlayingActivity) {
        let clock = ManualClock(), perl = ScriptedProvider(kind: .perl)
        let service = Fixtures.service([perl], clock: clock, services: services)
        service.start()
        await settle()
        let opened = OpenedPlayers()
        let activity = NowPlayingActivity(service: service, settings: services.settings, open: { opened.ids.append($0) })
        return (service, perl, clock, activity)
    }

    @Test func kindDefaults() {
        let kind = NowPlayingActivity.kind
        #expect(kind.id == .nowPlaying)
        #expect(kind.module == .media)
        #expect(kind.defaultPriority == .ongoing)
        #expect(kind.canPeekOnChange && kind.peeksOnChangeByDefault)
    }

    @Test func activeWhileThereIsASessionWithPriorityByState() async {
        let (_, perl, _, activity) = await running()
        #expect(!activity.isActive)
        perl.emit(.nowPlaying(Fixtures.track("A")))
        await settle()
        #expect(activity.isActive)
        #expect(activity.priority == .ongoing)
        #expect(activity.slot == .short)
        #expect(activity.opensWidget == .media)
        #expect(activity.middleLabel == "A")
        perl.emit(.nowPlaying(Fixtures.track("A", playing: false)))
        await settle()
        #expect(activity.priority == .passive)
        #expect(activity.accessibilityValue == MediaStrings.paused)
    }

    @Test func hidesAfterThePausedTimeoutAndComesBackOnResume() async {
        let services = CrannyServices.preview()
        let (_, perl, clock, activity) = await running(services)
        perl.emit(.nowPlaying(Fixtures.track("A", playing: false)))
        await settle()
        await clock.advance(by: .seconds(29))
        #expect(activity.isActive)
        await clock.advance(by: .seconds(1))
        #expect(!activity.isActive)                                        // 30 s by default

        perl.emit(.nowPlaying(Fixtures.track("A", playing: true)))
        await settle()
        #expect(activity.isActive)                                         // auto-unhide on resume

        services.settings[MediaSettings.hidePausedAfterSeconds] = 0          // never hide
        perl.emit(.nowPlaying(Fixtures.track("A", playing: false)))
        await settle()
        await clock.advance(by: .seconds(3600))
        #expect(activity.isActive)
    }

    @Test func resumingBeforeTheTimeoutCancelsIt() async {
        let (_, perl, clock, activity) = await running()
        perl.emit(.nowPlaying(Fixtures.track("A", playing: false)))
        await settle()
        await clock.advance(by: .seconds(20))
        perl.emit(.nowPlaying(Fixtures.track("A", playing: true)))
        await settle()
        await clock.advance(by: .seconds(20))
        perl.emit(.nowPlaying(Fixtures.track("A", playing: false)))
        await settle()
        await clock.advance(by: .seconds(20))
        #expect(activity.isActive)                                         // a fresh 30 s after the second pause
    }

    @Test func revisionFollowsNewTracks() async {
        let (_, perl, clock, activity) = await running()
        perl.emit(.nowPlaying(Fixtures.track("A")))
        await settle()
        #expect(activity.revision == 0)
        perl.emit(.nowPlaying(Fixtures.track("B")))
        await settle()
        await clock.advance(by: .milliseconds(300))
        #expect(activity.revision == 1)
    }

    @Test func swipesChangeTracksAndHonourInvert() async {
        let services = CrannyServices.preview()
        let (_, perl, _, activity) = await running(services)
        #expect(activity.handle(.swipeLeft) == false)                     // nothing playing: not handled
        perl.emit(.nowPlaying(Fixtures.track("A")))
        await settle()
        #expect(activity.handle(.swipeLeft))
        #expect(activity.handle(.swipeRight))
        await settle()
        #expect(perl.commands == [.nextTrack, .previousTrack])
        services.settings[CoreSettings.invertTrackSwipe] = true
        #expect(activity.handle(.swipeLeft))
        await settle()
        #expect(perl.commands.last == .previousTrack)
        services.settings[CoreSettings.trackSwipe] = false
        #expect(activity.handle(.swipeLeft) == false)
    }

    @Test func accessibilityLabelValueAndActions() async throws {
        let (_, perl, clock, activity) = await running()
        perl.emit(.nowPlaying(Fixtures.track("Midnight Window", artist: "The Example Band", elapsed: 84, duration: 215, timestamp: clock.now)))
        await settle()
        #expect(activity.accessibilityLabel == MediaStrings.nowPlayingLabel(title: "Midnight Window", artist: "The Example Band"))
        #expect(activity.accessibilityValue == MediaStrings.timeLeft(131))
        let ids = activity.actions.map(\.id)
        #expect(ids == ["playPause", "next", "previous", "open"])
        let playPause = try #require(activity.actions.first)
        #expect(playPause.title == MediaStrings.pause)
        playPause.perform()
        await settle()
        #expect(perl.commands == [.togglePlayPause])
    }

    @Test func sampleInstanceIsSelfContained() async {
        let services = CrannyServices.preview()
        let sample = NowPlayingActivity(service: SampleMedia.service(settings: services.settings, environment: services.environment,
                                                                     permissions: services.permissions),
                                        settings: services.settings, open: { _ in })
        #expect(sample.isActive)
        #expect(sample.palette != nil)                                     // album light from the generated artwork
        #expect(sample.accessibilityLabel.contains(SampleMedia.title))
        #expect(services.nowPlaying == nil)                                // never published as the live source
    }
}

@MainActor private final class OpenedPlayers { var ids: [String] = [] }
