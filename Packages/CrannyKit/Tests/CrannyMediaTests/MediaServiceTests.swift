// MediaService with scripted providers and a manual clock: restart backoff 0.5/2/8 s, failover after 3 failures in
// 60 s, optimistic commands and their confirmation (refresh, then the player's state again), track-change debounce,
// filters, the elected player before filters, Automation denials, artwork cache (ARCHITECTURE.md §6.5, §10.2).
import CoreGraphics
import CrannyCore
import Foundation
import Testing
@testable import CrannyMedia

@Suite("Media service") @MainActor struct MediaServiceTests {
    @Test func startsTheFirstProviderAndPublishesSnapshots() async {
        let clock = ManualClock(), perl = ScriptedProvider(kind: .perl)
        let service = Fixtures.service([perl], clock: clock)
        service.start()
        await settle()
        #expect(perl.starts == 1)
        #expect(service.status == .starting(.perl))
        perl.emit(.nowPlaying(Fixtures.track("A")))
        await settle()
        #expect(service.status == .running(.perl))
        #expect(service.nowPlaying?.title == "A")
        #expect(service.lastSourceBundleID == "com.apple.Music")
        #expect(service.recentSources == ["com.apple.Music"])
    }

    @Test func restartsWithBackoffThenFailsOver() async {
        let clock = ManualClock(), perl = ScriptedProvider(kind: .perl), ruby = ScriptedProvider(kind: .ruby)
        let service = Fixtures.service([perl, ruby], clock: clock)
        service.start()
        await settle()

        perl.emit(.unavailable(.exited(status: 9)))                      // kill -9
        await settle()
        #expect(service.status == .restarting(.perl))
        #expect(service.lastError == .provider(.perl, .exited(status: 9)))
        await clock.advance(by: .milliseconds(499))
        #expect(perl.starts == 1)
        await clock.advance(by: .milliseconds(1))
        #expect(perl.starts == 2)                                         // restarted after 0.5 s

        perl.emit(.unavailable(.exited(status: 9)))
        await settle()
        await clock.advance(by: .milliseconds(1999))
        #expect(perl.starts == 2)
        await clock.advance(by: .milliseconds(1))
        #expect(perl.starts == 3)                                         // then after 2 s

        perl.emit(.unavailable(.noHandshake))                             // third failure within 60 s
        await settle()
        #expect(ruby.starts == 1)
        #expect(service.status == .starting(.ruby))
        ruby.emit(.nowPlaying(Fixtures.track("A")))
        await settle()
        #expect(service.status == .running(.ruby))
    }

    @Test func spreadOutFailuresWaitEightSeconds() async {
        let clock = ManualClock(), perl = ScriptedProvider(kind: .perl)
        let service = Fixtures.service([perl], clock: clock)
        service.start()
        await settle()
        for (wait, delay) in [(Duration.seconds(0), Duration.milliseconds(500)), (.seconds(40), .seconds(2)), (.seconds(40), .seconds(8))] {
            await clock.advance(by: wait)
            let starts = perl.starts
            perl.emit(.unavailable(.exited(status: 1)))
            await settle()
            await clock.advance(by: delay - .milliseconds(1))
            #expect(perl.starts == starts)
            await clock.advance(by: .milliseconds(1))
            #expect(perl.starts == starts + 1)
        }
    }

    @Test func missingProvidersAreSkippedAndAnEmptyChainIsUnavailable() async {
        let clock = ManualClock(), ruby = ScriptedProvider(kind: .ruby)
        let service = Fixtures.service([nil, ruby], clock: clock)          // no perl/dylib
        service.start()
        await settle()
        #expect(ruby.starts == 1)

        let empty = Fixtures.service([nil], clock: clock)
        empty.start()
        await settle()
        #expect(empty.status == .unavailable)
        #expect(empty.lastError == .noProvider)
        #expect(empty.supportsCommands == false)
    }

    @Test func retryStartsTheChainAgain() async {
        let clock = ManualClock(), perl = ScriptedProvider(kind: .perl)
        let service = Fixtures.service([perl], clock: clock)
        service.start()
        await settle()
        for _ in 0..<3 {
            perl.emit(.unavailable(.exited(status: 1)))
            await settle()
            await clock.advance(by: .seconds(2))
        }
        #expect(service.status == .unavailable)
        service.restart()
        await settle()
        #expect(service.status == .starting(.perl))
        #expect(service.lastError == nil)
    }

    @Test func commandsAreOptimisticAndReachTheProvider() async {
        let clock = ManualClock(), perl = ScriptedProvider(kind: .perl)
        let service = Fixtures.service([perl], clock: clock)
        service.start()
        await settle()
        perl.emit(.nowPlaying(Fixtures.track("A", playing: true, elapsed: 10, timestamp: clock.now)))
        await settle()
        await clock.advance(by: .seconds(5))

        #expect(await service.send(.togglePlayPause))
        #expect(service.nowPlaying?.isPlaying == false)                   // before the provider's next state
        #expect(service.nowPlaying?.elapsed == 15)                        // frozen at the interpolated position
        await service.send(.seek(to: 120))
        #expect(service.nowPlaying?.elapsed == 120)
        await service.send(.seek(to: 999))
        #expect(service.nowPlaying?.elapsed == 200)                       // clamped to the duration
        await service.send(.nextTrack)
        #expect(perl.commands == [.togglePlayPause, .seek(to: 120), .seek(to: 999), .nextTrack])

        perl.emit(.nowPlaying(Fixtures.track("A", playing: true, elapsed: 121, timestamp: clock.now)))
        await settle()
        #expect(service.nowPlaying?.isPlaying == true)                    // the provider is authoritative
    }

    @Test func readOnlyProvidersReceiveNoCommandsAndNothingChanges() async {
        let clock = ManualClock(), script = ScriptedProvider(kind: .appleScript, supportsCommands: false)
        let service = Fixtures.service([script], clock: clock)
        service.start()
        await settle()
        script.emit(.nowPlaying(Fixtures.track("A")))
        await settle()
        #expect(await service.send(.nextTrack) == false)
        #expect(await service.send(.togglePlayPause) == false)
        #expect(await service.send(.seek(to: 100)) == false)
        #expect(script.commands.isEmpty)
        #expect(service.nowPlaying?.isPlaying == true)                    // no optimistic flip for a read-only source
        #expect(service.nowPlaying?.elapsed == 10)
    }

    /// A playing session at `clock.now`, elapsed 10 s.
    private func playing() async -> (MediaService, ScriptedProvider, ManualClock) {
        let clock = ManualClock(), perl = ScriptedProvider(kind: .perl)
        let service = Fixtures.service([perl], clock: clock)
        service.start()
        await settle()
        perl.emit(.nowPlaying(Fixtures.track("A", playing: true, elapsed: 10, timestamp: clock.now)))
        await settle()
        return (service, perl, clock)
    }

    @Test func aStateAfterTheCommandConfirmsIt() async {
        let (service, perl, clock) = await playing()
        #expect(await service.send(.pause))
        perl.emit(.nowPlaying(Fixtures.track("A", playing: false, elapsed: 10, timestamp: clock.now)))
        await settle()
        await clock.advance(by: .seconds(5))
        #expect(perl.refreshes == 0)                                      // confirmed: nothing to ask
        #expect(service.nowPlaying?.isPlaying == false)
    }

    @Test func anIgnoredCommandAsksForTheStateThenShowsThePlayersStateAgain() async {
        // The bridge de-duplicates identical states: a pause the player ignores produces no new state at all.
        let (service, perl, clock) = await playing()
        #expect(await service.send(.pause))
        #expect(service.nowPlaying?.isPlaying == false)                   // optimistic
        await settle()                                                    // the confirmation task starts its sleep
        await clock.advance(by: MediaService.confirmationWindow - .milliseconds(1))
        #expect(perl.refreshes == 0)
        await clock.advance(by: .milliseconds(1))
        #expect(perl.refreshes == 1)                                      // nothing confirmed it: "refresh state"
        #expect(service.nowPlaying?.isPlaying == false)
        await clock.advance(by: MediaService.rollbackWindow)
        #expect(service.nowPlaying?.isPlaying == true)                    // the player's last state again …
        let position = service.nowPlaying?.position(at: clock.now) ?? 0
        #expect(abs(position - 11.5) < 1e-6)                              // … still counting from its anchor
    }

    @Test func theRefreshedStateIsAuthoritative() async {
        let (service, perl, clock) = await playing()
        await service.send(.seek(to: 120))
        #expect(service.nowPlaying?.elapsed == 120)
        await settle()
        await clock.advance(by: MediaService.confirmationWindow)
        #expect(perl.refreshes == 1)
        perl.emit(.nowPlaying(Fixtures.track("A", playing: true, elapsed: 10.8, timestamp: clock.now)))   // the seek was ignored
        await settle()
        #expect(service.nowPlaying?.elapsed == 10.8)
        await clock.advance(by: .seconds(5))
        #expect(service.nowPlaying?.elapsed == 10.8)                      // no second rollback
        #expect(perl.refreshes == 1)
    }

    @Test func aRefusedCommandIsUndoneAtOnce() async {
        let (service, perl, _) = await playing()
        perl.accepts = false                                              // `ack ok:false`, a failed script, no answer
        #expect(await service.send(.togglePlayPause) == false)
        #expect(service.nowPlaying?.isPlaying == true)
        #expect(await service.send(.seek(to: 150)) == false)
        #expect(service.nowPlaying?.elapsed == 10)
        #expect(perl.commands == [.togglePlayPause, .seek(to: 150)])
    }

    @Test func theNewestCommandIsTheOneConfirmed() async {
        let (service, perl, clock) = await playing()
        await service.send(.pause)
        await settle()
        await clock.advance(by: .milliseconds(500))
        await service.send(.play)                                         // restarts the confirmation window
        await settle()
        await clock.advance(by: .milliseconds(500))
        #expect(perl.refreshes == 0)
        await clock.advance(by: .milliseconds(300))
        #expect(perl.refreshes == 1)
    }

    @Test func trackChangesAreDebouncedAndCountOnlyWhilePlaying() async {
        let clock = ManualClock(), perl = ScriptedProvider(kind: .perl)
        let service = Fixtures.service([perl], clock: clock)
        service.start()
        await settle()
        perl.emit(.nowPlaying(Fixtures.track("A")))                       // first snapshot after launch
        await settle()
        await clock.advance(by: .seconds(1))
        #expect(service.trackChangeCount == 0)

        perl.emit(.nowPlaying(Fixtures.track("B", artist: nil)))          // partial metadata burst
        await settle()
        await clock.advance(by: .milliseconds(200))
        perl.emit(.nowPlaying(Fixtures.track("B", artist: "Band")))
        await settle()
        await clock.advance(by: .milliseconds(299))
        #expect(service.trackChangeCount == 0)
        await clock.advance(by: .milliseconds(1))
        #expect(service.trackChangeCount == 1)

        perl.emit(.nowPlaying(Fixtures.track("C", playing: false)))       // skipped while paused: no peek
        await settle()
        await clock.advance(by: .seconds(1))
        #expect(service.trackChangeCount == 1)

        perl.emit(.nowPlaying(Fixtures.track("D")))
        await settle()
        await clock.advance(by: .milliseconds(100))
        perl.emit(.nowPlaying(Fixtures.track("C", playing: false)))       // back before the debounce
        await settle()
        await clock.advance(by: .seconds(1))
        #expect(service.trackChangeCount == 1)
    }

    @Test func filtersApplyLiveWhenSettingsChange() async {
        let clock = ManualClock(), perl = ScriptedProvider(kind: .perl), services = CrannyServices.preview()
        let service = Fixtures.service([perl], clock: clock, services: services)
        service.start()
        await settle()
        perl.emit(.nowPlaying(Fixtures.track("Video", bundleID: "com.google.Chrome")))
        await settle()
        #expect(service.nowPlaying != nil)
        services.settings[MediaSettings.showsBrowserMedia] = false
        await settle()
        #expect(service.nowPlaying == nil)
        services.settings[MediaSettings.showsBrowserMedia] = true
        services.settings[MediaSettings.ignoredBundleIDs] = ["com.google.Chrome"]
        await settle()
        #expect(service.nowPlaying == nil)
        #expect(service.recentSources == ["com.google.Chrome"])           // still offered in Settings
        services.settings[MediaSettings.ignoredBundleIDs] = []
        await settle()
        #expect(service.nowPlaying?.title == "Video")
    }

    @Test func artworkIsDecodedCachedAndKeptForTheSameTrack() async throws {
        let clock = ManualClock(), perl = ScriptedProvider(kind: .perl)
        let service = Fixtures.service([perl], clock: clock)
        service.start()
        await settle()
        let a = Fixtures.track("A", itemID: "a"), b = Fixtures.track("B", itemID: "b")
        perl.emit(.nowPlaying(a))
        perl.emit(.artwork(trackKey: "a", data: Fixtures.png(red: 0.9, green: 0.1, blue: 0.1)))
        #expect(await eventually { service.artwork != nil })
        let redAccent = try #require(service.palette?.accent)
        #expect(redAccent.r > redAccent.b)

        perl.emit(.nowPlaying(Fixtures.track("A", itemID: "a", elapsed: 50)))   // a seek: same key, artwork stays
        await settle()
        #expect(service.artwork != nil)

        perl.emit(.artwork(trackKey: "b", data: Fixtures.png(red: 0.1, green: 0.2, blue: 0.9)))  // early art for B
        try await Task.sleep(for: .milliseconds(100))
        await settle()
        #expect(service.palette?.accent == redAccent)                     // only cached

        perl.emit(.nowPlaying(b))
        await settle()
        let blue = try #require(service.palette?.accent)
        #expect(blue.b > blue.r)                                          // cache hit: applied at once

        perl.emit(.nowPlaying(Fixtures.track("C", itemID: "c")))          // no artwork for C
        await settle()
        #expect(service.artwork != nil)                                   // the previous art stays briefly …
        await clock.advance(by: .milliseconds(600))
        #expect(service.artwork == nil)                                   // … then the missing-artwork tile
        #expect(service.palette == nil)
    }

    @Test func theElectedPlayerIsKeptBeforeFilters() async {
        let clock = ManualClock(), perl = ScriptedProvider(kind: .perl), services = CrannyServices.preview()
        let service = Fixtures.service([perl], clock: clock, services: services)
        service.start()
        await settle()
        #expect(service.reportedPlayerPID == nil)                         // unknown until the first state
        services.settings[MediaSettings.ignoredBundleIDs] = ["com.google.Chrome"]
        perl.emit(.electedPlayer(pid: 42, bundleID: "com.google.Chrome"))
        perl.emit(.nowPlaying(Fixtures.track("Video", bundleID: "com.google.Chrome")))
        await settle()
        #expect(service.nowPlaying == nil)                                // hidden by Ignore apps …
        #expect(service.reportedPlayerPID == 42)                          // … but the helper saw it
        #expect(service.reportedPlayerBundleID == "com.google.Chrome")
        perl.emit(.unavailable(.exited(status: 9)))
        await settle()
        #expect(service.reportedPlayerPID == 42)                          // kept while restarting …
        await clock.advance(by: .milliseconds(500))
        #expect(service.reportedPlayerPID == nil)                         // … unknown again for the new helper
    }

    @Test func anAutomationDenialIsRecorded() async {
        let clock = ManualClock(), script = ScriptedProvider(kind: .appleScript), services = CrannyServices.preview()
        let service = Fixtures.service([script], clock: clock, services: services)
        service.start()
        await settle()
        script.emit(.permissionDenied(bundleID: "com.apple.Music"))
        await settle()
        #expect(services.permissions.status(.automation(bundleID: "com.apple.Music")) == .denied)
        #expect(service.lastError == .provider(.appleScript, .notPermitted))
        #expect(service.status == .starting(.appleScript))                // a denial is not a failure: no restart
        #expect(script.starts == 1)
    }

    @Test func differentArtworkForTheSameTrackReplacesIt() async throws {
        let clock = ManualClock(), perl = ScriptedProvider(kind: .perl)
        let service = Fixtures.service([perl], clock: clock)
        service.start()
        await settle()
        perl.emit(.nowPlaying(Fixtures.track("A", itemID: "a")))
        perl.emit(.artwork(trackKey: "a", data: Fixtures.png(red: 0.9, green: 0.1, blue: 0.1)))   // placeholder first
        #expect(await eventually { service.artwork != nil })
        let blue = Fixtures.png(red: 0.1, green: 0.2, blue: 0.9)
        perl.emit(.artwork(trackKey: "a", data: blue))                    // then the real picture
        #expect(await eventually { (service.palette?.accent).map { $0.b > $0.r } ?? false })
        let image = try #require(service.artwork)
        perl.emit(.artwork(trackKey: "a", data: blue))                    // the same picture again: kept, not decoded
        try await Task.sleep(for: .milliseconds(100))
        await settle()
        #expect(service.artwork === image)
        #expect(service.artworkKey == "a")
    }

    @Test func aLateDecodeNeverReplacesANewerPicture() async throws {
        let clock = ManualClock(), perl = ScriptedProvider(kind: .perl)
        let service = Fixtures.service([perl], clock: clock)
        service.start()
        await settle()
        perl.emit(.nowPlaying(Fixtures.track("A", itemID: "a")))
        perl.emit(.artwork(trackKey: "a", data: Fixtures.png(red: 0.9, green: 0.1, blue: 0.1, side: 1024)))   // slow
        perl.emit(.artwork(trackKey: "a", data: Fixtures.png(red: 0.1, green: 0.2, blue: 0.9, side: 8)))      // fast
        #expect(await eventually { service.artwork != nil })
        try await Task.sleep(for: .milliseconds(300))
        await settle()
        let accent = try #require(service.palette?.accent)
        #expect(accent.b > accent.r)                                      // the newer (blue) picture stays
    }

    @Test func sampleSeedNeverStartsAProvider() async {
        let service = SampleMedia.previewService()
        #expect(service.status == .running(.sample))
        #expect(service.nowPlaying?.title == SampleMedia.title)
        #expect(service.artwork != nil)
        service.start()                                                   // a no-op for a seeded service
        #expect(service.status == .running(.sample))
        #expect(await service.send(.togglePlayPause) == false)            // no provider: only the sample changes
        #expect(service.nowPlaying?.isPlaying == false)
    }
}
