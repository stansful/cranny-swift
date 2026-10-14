// Pure policies of the media service: restart/failover (ProviderSupervisor), track-change debounce rules
// (TrackChangeDetector) and session filters (MediaFilter).
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
