// MediaService with scripted providers and a manual clock: restart backoff 0.5/2/8 s, failover after 3 failures in
// 60 s, optimistic commands, track-change debounce, filters, artwork cache (ARCHITECTURE.md §6.5, §10.2).
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

    @Test func readOnlyProvidersReceiveNoCommands() async {
        let clock = ManualClock(), script = ScriptedProvider(kind: .appleScript, supportsCommands: false)
        let service = Fixtures.service([script], clock: clock)
        service.start()
        await settle()
        script.emit(.nowPlaying(Fixtures.track("A")))
        await settle()
        #expect(await service.send(.nextTrack) == false)
        #expect(script.commands.isEmpty)
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
