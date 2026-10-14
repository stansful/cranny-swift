// Pure policies of the media service: restart/failover (ProviderSupervisor), track-change debounce rules
// (TrackChangeDetector), session filters (MediaFilter), the widget's time labels (PlaybackTime, PlaybackTick) and
// scroll-to-seek over the scrubber (ScrollSeek).
import CrannyCore
import Foundation
import Testing
@testable import CrannyMedia

private let t0 = Date(timeIntervalSince1970: 1_000_000)

@Suite("Provider supervisor") struct ProviderSupervisorTests {
    @Test func backoffThenFailoverAfterThreeFailuresInAMinute() {
        var s = ProviderSupervisor()
        #expect(s.recordFailure(at: t0) == .restart(after: .milliseconds(500)))
        #expect(s.recordFailure(at: t0.addingTimeInterval(1)) == .restart(after: .seconds(2)))
        #expect(s.recordFailure(at: t0.addingTimeInterval(4)) == .failover)
        #expect(s.failures.isEmpty)
    }

    @Test func spreadOutFailuresReachTheEightSecondStep() {
        var s = ProviderSupervisor()
        #expect(s.recordFailure(at: t0) == .restart(after: .milliseconds(500)))
        #expect(s.recordFailure(at: t0.addingTimeInterval(40)) == .restart(after: .seconds(2)))
        // 80 s: only two failures in the last minute → no failover, third consecutive failure → 8 s.
        #expect(s.recordFailure(at: t0.addingTimeInterval(80)) == .restart(after: .seconds(8)))
        #expect(s.recordFailure(at: t0.addingTimeInterval(130)) == .restart(after: .seconds(8)))
    }

    @Test func aHealthyMinuteResetsTheBackoff() {
        var s = ProviderSupervisor()
        _ = s.recordFailure(at: t0)
        _ = s.recordFailure(at: t0.addingTimeInterval(10))
        #expect(s.recordFailure(at: t0.addingTimeInterval(75)) == .restart(after: .milliseconds(500)))
    }

    @Test func resetForgetsFailures() {
        var s = ProviderSupervisor()
        _ = s.recordFailure(at: t0)
        _ = s.recordFailure(at: t0)
        s.reset()
        #expect(s.recordFailure(at: t0) == .restart(after: .milliseconds(500)))
    }
}

@Suite("Track change detector") @MainActor struct TrackChangeDetectorTests {
    @Test func firstSnapshotAfterLaunchNeverCounts() {
        var d = TrackChangeDetector()
        #expect(d.observe(Fixtures.track("A")) == false)
        #expect(d.settledKey == Fixtures.track("A").trackKey)
    }

    @Test func aNewPlayingTrackCountsAfterTheDebounce() {
        var d = TrackChangeDetector()
        _ = d.observe(Fixtures.track("A"))
        let b = Fixtures.track("B")
        #expect(d.observe(b) == true)                    // start the 300-ms debounce
        #expect(d.debounceElapsed(current: b) == true)
        #expect(d.settledKey == b.trackKey)
    }

    @Test func burstsRestartTheDebounceAndCountOnce() {
        var d = TrackChangeDetector()
        _ = d.observe(Fixtures.track("A"))
        #expect(d.observe(Fixtures.track("B", artist: nil)) == true)      // title first …
        let full = Fixtures.track("B", artist: "Band")
        #expect(d.observe(full) == true)                                  // … then the artist: restart
        #expect(d.observe(full) == false)                                 // the same pending key again
        #expect(d.debounceElapsed(current: full) == true)
        #expect(d.debounceElapsed(current: full) == false)
    }

    @Test func changeWhilePausedSettlesSilently() {
        var d = TrackChangeDetector()
        _ = d.observe(Fixtures.track("A"))
        let paused = Fixtures.track("B", playing: false)
        #expect(d.observe(paused) == true)
        #expect(d.debounceElapsed(current: paused) == false)
        #expect(d.settledKey == paused.trackKey)
        #expect(d.observe(Fixtures.track("B", playing: true)) == false)   // pressing play is not a new track
    }

    @Test func returningToTheSettledTrackCancels() {
        var d = TrackChangeDetector()
        let a = Fixtures.track("A")
        _ = d.observe(a)
        _ = d.observe(Fixtures.track("B"))
        #expect(d.observe(a) == false)
        #expect(d.pendingKey == nil)
        #expect(d.debounceElapsed(current: a) == false)
    }

    @Test func aTrackAfterNothingPlayingCountsAgain() {
        var d = TrackChangeDetector()
        let a = Fixtures.track("A")
        _ = d.observe(a)
        #expect(d.observe(nil) == false)
        #expect(d.observe(a) == true)
        #expect(d.debounceElapsed(current: a) == true)
    }

    @Test func launchingWithNothingPlayingThenATrackCounts() {
        var d = TrackChangeDetector()
        #expect(d.observe(nil) == false)
        let a = Fixtures.track("A")
        #expect(d.observe(a) == true)
        #expect(d.debounceElapsed(current: a) == true)
    }
}

@Suite("Media filter") @MainActor struct MediaFilterTests {
    @Test func ignoredAppsAreHiddenCaseInsensitively() {
        let filter = MediaFilter(ignoredBundleIDs: ["com.Spotify.client"], showsBrowserMedia: true)
        #expect(filter.apply(Fixtures.track("A", bundleID: "com.spotify.client")) == nil)
        #expect(filter.apply(Fixtures.track("A", bundleID: "com.apple.Music")) != nil)
        #expect(filter.apply(nil) == nil)
    }

    @Test func theHostingAppCountsToo() {
        var np = Fixtures.track("Video", bundleID: "com.google.Chrome.helper")
        np.parentBundleID = "com.google.Chrome"
        #expect(MediaFilter(ignoredBundleIDs: ["com.google.Chrome"]).apply(np) == nil)
        #expect(MediaFilter(showsBrowserMedia: false).apply(np) == nil)
        #expect(MediaFilter(showsBrowserMedia: true).apply(np) != nil)
    }

    @Test("Browsers", arguments: ["com.apple.Safari", "com.google.Chrome", "com.google.Chrome.canary", "org.mozilla.firefox",
                                  "com.microsoft.edgemac.Dev", "company.thebrowser.Browser", "ru.yandex.desktop.yandex-browser"])
    func browsers(_ id: String) {
        #expect(BrowserCatalog.isBrowser(id))
        #expect(MediaFilter(showsBrowserMedia: false).apply(Fixtures.track("A", bundleID: id)) == nil)
    }

    @Test("Players are not browsers", arguments: ["com.apple.Music", "com.spotify.client", "com.apple.podcasts", "com.colliderli.iina"])
    func players(_ id: String) {
        #expect(!BrowserCatalog.isBrowser(id))
    }
}

@Suite("Playback time") struct PlaybackTimeTests {
    @Test func labelsAddUpToTheDuration() {
        let sample = PlaybackTime(position: 84.6, duration: 215)          // DESIGN.md §7.1: 1:24 … −2:11
        #expect(sample.elapsed == 84)
        #expect(sample.remaining == 131)
        for position in stride(from: 0.0, through: 216, by: 0.37) {
            let time = PlaybackTime(position: position, duration: 215.5)
            #expect(time.elapsed + time.remaining == 215)
        }
        #expect(PlaybackTime(position: 300, duration: 215) == PlaybackTime(position: 215, duration: 215))
        #expect(PlaybackTime(position: 300, duration: 215).remaining == 0)
        #expect(PlaybackTime(position: -3, duration: 215).elapsed == 0)
        #expect(PlaybackTime(position: .nan, duration: .infinity).remaining == 0)
    }

    @Test func ticksLandJustAfterEachWholeSecond() throws {
        let margin = PlaybackTick.margin
        let delay = try #require(PlaybackTick.delay(position: 84.6, rate: 1, isPlaying: true, duration: 215))
        #expect(abs(delay - (0.4 + margin)) < 1e-9)
        #expect(abs((84.6 + delay).rounded(.down) - 85) < 1e-9)           // the label reads the new second
        let onBoundary = try #require(PlaybackTick.delay(position: 84, rate: 1, isPlaying: true, duration: 215))
        #expect(abs(onBoundary - (1 + margin)) < 1e-9)
        let faster = try #require(PlaybackTick.delay(position: 84.6, rate: 2, isPlaying: true, duration: 215))
        #expect(abs(faster - (0.2 + margin)) < 1e-9)                      // 2× playback: seconds pass twice as fast
        let live = try #require(PlaybackTick.delay(position: 10.5, rate: 0, isPlaying: true, duration: nil))
        #expect(abs(live - (0.5 + margin)) < 1e-9)
    }

    @Test func noTicksWhenNothingChanges() {
        #expect(PlaybackTick.delay(position: 84.6, rate: 1, isPlaying: false, duration: 215) == nil)   // paused
        #expect(PlaybackTick.delay(position: 215, rate: 1, isPlaying: true, duration: 215) == nil)     // at the end
        #expect(PlaybackTick.delay(position: .nan, rate: 1, isPlaying: true, duration: 215) == nil)
    }
}

@Suite("Scroll to seek") struct ScrollSeekTests {
    @Test func aLongScrollPreviewsAllOfItsTravelAndSeeksOnRelease() throws {
        // 120 pt over a 180-pt scrubber from 10 %: the preview follows every point (a committing zone would have
        // stopped at 40 pt), and the release seeks once.
        var seek = ScrollSeek()
        var preview = 0.0
        for step in 1...12 { preview = seek.track(translation: CGFloat(step * 10), width: 180, current: 0.1) }
        #expect(abs(preview - (0.1 + 120.0 / 180)) < 1e-9)
        let ended = seek.end(.released, preview: preview, duration: 300)
        let target = try #require(ended)
        #expect(abs(target - preview * 300) < 1e-9)
        #expect(seek.start == nil)
    }

    @Test func aSystemCancelSeeksNowhere() {
        var seek = ScrollSeek()
        let preview = seek.track(translation: 30, width: 180, current: 0.5)
        #expect(seek.end(.cancelled, preview: preview, duration: 300) == nil)
        #expect(seek.start == nil)                                         // the next touch starts afresh
    }

    @Test func theTouchStartsWhereTheTrackWas() {
        var seek = ScrollSeek()
        #expect(seek.track(translation: 0, width: 200, current: 0.25) == 0.25)
        // Playback moves on during the touch: the preview stays relative to where the touch began.
        #expect(seek.track(translation: 20, width: 200, current: 0.3) == 0.35)
        _ = seek.end(.released, preview: 0.35, duration: 100)
        #expect(seek.track(translation: 0, width: 200, current: 0.3) == 0.3)
    }

    @Test func previewAndTargetStayOnTheTrack() {
        var seek = ScrollSeek()
        #expect(seek.track(translation: -500, width: 180, current: 0.1) == 0)
        #expect(seek.track(translation: 500, width: 180, current: 0.1) == 1)
        #expect(seek.end(.released, preview: 1.4, duration: 200) == 200)
        #expect(seek.end(.released, preview: nil, duration: 200) == nil)  // nothing previewed
        #expect(seek.end(.released, preview: 0.5, duration: nil) == nil)  // a live stream
        #expect(seek.end(.released, preview: 0.5, duration: .infinity) == nil)
        var zeroWidth = ScrollSeek()
        #expect(zeroWidth.track(translation: 10, width: 0, current: 0.5) == 1)    // a zero width never divides by 0
    }
}
