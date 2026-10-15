// The Now Playing activity: activity rules of DESIGN.md §9.2 (P2/P3, hidden after N s paused, auto-unhide,
// revision = new tracks, swipes → previous/next with Invert), the shared track-swipe rule of the widget, read-only
// sources, with scripted providers and a manual clock. Its priority depends on whether music plays, not on the
// snapshot, so a seek does not re-evaluate the canvas or the open header that read it.
import CrannyCore
import Foundation
import Observation
import os
import Testing
@testable import CrannyMedia

@Suite("Now Playing activity") @MainActor struct NowPlayingActivityTests {
    private func running(_ services: CrannyServices = .preview(), provider perl: ScriptedProvider = ScriptedProvider(kind: .perl))
        async -> (MediaService, ScriptedProvider, ManualClock, NowPlayingActivity) {
        let clock = ManualClock()
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

    /// A seek or new metadata invalidates nothing that reads the priority (raw Observation: any write would count);
    /// playback starting or stopping does, also through an optimistic command.
    @Test func priorityIsInvalidatedOnlyWhenPlaybackStartsOrStops() async {
        let (service, perl, clock, activity) = await running()
        perl.emit(.nowPlaying(Fixtures.track("A", elapsed: 10, timestamp: clock.now)))
        await settle()
        #expect(service.isPlaying && activity.priority == .ongoing)
        let invalidations = OSAllocatedUnfairLock(initialState: 0)
        func track() {
            withObservationTracking { _ = activity.priority } onChange: { invalidations.withLock { $0 += 1 } }
        }
        track()

        perl.emit(.nowPlaying(Fixtures.track("A", elapsed: 60, timestamp: clock.now)))                      // a seek
        await settle()
        perl.emit(.nowPlaying(Fixtures.track("A", artist: "Other", elapsed: 60, timestamp: clock.now)))     // metadata
        await settle()
        #expect(service.nowPlaying?.elapsed == 60 && service.nowPlaying?.artist == "Other")
        #expect(invalidations.withLock { $0 } == 0)

        perl.emit(.nowPlaying(Fixtures.track("A", artist: "Other", playing: false, elapsed: 60, timestamp: clock.now)))
        await settle()
        #expect(invalidations.withLock { $0 } == 1)
        #expect(!service.isPlaying && activity.priority == .passive)

        track()
        #expect(await service.send(.play))                                       // optimistic: before the provider
        #expect(invalidations.withLock { $0 } == 2)
        #expect(service.isPlaying && activity.priority == .ongoing)
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

    @Test func anIgnoredPauseDoesNotHideMusicThatKeepsPlaying() async {
        // The optimistic pause starts the paused timeout; when no state confirms it, the player's (playing) state
        // comes back and the timeout is cancelled.
        let (service, perl, clock, activity) = await running()
        perl.emit(.nowPlaying(Fixtures.track("A", playing: true, timestamp: clock.now)))
        await settle()
        await service.send(.pause)
        #expect(activity.priority == .passive)
        await settle()
        await clock.advance(by: MediaService.confirmationWindow)              // asks the provider again …
        await clock.advance(by: MediaService.rollbackWindow)                  // … no answer: the player's state
        #expect(activity.priority == .ongoing)
        await clock.advance(by: .seconds(60))
        #expect(activity.isActive)
    }

    @Test func readOnlySourcesOfferOnlyOpen() async {
        let (_, script, _, activity) = await running(provider: ScriptedProvider(kind: .appleScript, supportsCommands: false))
        script.emit(.nowPlaying(Fixtures.track("A")))
        await settle()
        #expect(activity.actions.map(\.id) == ["open"])
        #expect(activity.handle(.swipeLeft) == false)
        await settle()
        #expect(script.commands.isEmpty)
    }

    @Test func trackSwipeIsOneRuleForCompactPeekAndWidget() async {
        let services = CrannyServices.preview()
        let (service, perl, _, _) = await running(services)
        let settings = services.settings
        #expect(TrackSwipe.command(for: .left, settings: settings, service: service) == nil)        // nothing playing
        perl.emit(.nowPlaying(Fixtures.track("A")))
        await settle()
        #expect(TrackSwipe.isEnabled(settings: settings, service: service))
        #expect(TrackSwipe.command(for: .left, settings: settings, service: service) == .nextTrack)
        #expect(TrackSwipe.command(for: .right, settings: settings, service: service) == .previousTrack)
        #expect(TrackSwipe.command(for: .up, settings: settings, service: service) == nil)
        #expect(TrackSwipe.command(for: ActivityGesture.swipeLeft, settings: settings, service: service) == .nextTrack)
        settings[CoreSettings.invertTrackSwipe] = true
        #expect(TrackSwipe.command(for: .left, settings: settings, service: service) == .previousTrack)
        settings[CoreSettings.trackSwipe] = false                         // Gestures ▸ Swipe sideways off
        #expect(!TrackSwipe.isEnabled(settings: settings, service: service))   // the widget does not even rubber-band
        #expect(TrackSwipe.command(for: .left, settings: settings, service: service) == nil)
        #expect(TrackSwipe.command(for: .right, settings: settings, service: service) == nil)
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
        #expect(sample.service.visualizer.allowsLive == false)             // never runs the system audio tap
    }
}

@MainActor private final class OpenedPlayers { var ids: [String] = [] }
