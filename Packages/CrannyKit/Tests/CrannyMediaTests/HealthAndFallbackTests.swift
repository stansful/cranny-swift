// The blocked-helper heuristic (R2 §5.4) with a manual clock and fed Core Audio state: only "no elected player
// (pid 0) while another process plays sound for 10 s" is degraded; filtered and untitled sessions are not. And the
// Apple Events fallback's notification payloads (Music, Spotify) → NowPlaying.
import CrannyCore
import Foundation
import Testing
@testable import CrannyMedia

@Suite("Blocked-helper heuristic") @MainActor struct BridgeHealthMonitorTests {
    private func running(_ kind: MediaProviderKind = .perl, services: CrannyServices = .preview())
        async -> (MediaService, ScriptedProvider, ManualClock, BridgeHealthMonitor) {
        let clock = ManualClock(), provider = ScriptedProvider(kind: kind)
        let service = Fixtures.service([provider], clock: clock, services: services)
        let monitor = BridgeHealthMonitor(service: service)
        service.health = monitor
        service.start()
        monitor.start(listensToCoreAudio: false)                          // tests feed `outputChanged`
        await settle()
        return (service, provider, clock, monitor)
    }

    private func report(_ provider: ScriptedProvider, pid: Int, bundleID: String? = nil, _ np: NowPlaying?) async {
        provider.emit(.electedPlayer(pid: pid, bundleID: bundleID))
        provider.emit(.nowPlaying(np))
        await settle()
    }

    @Test func noElectedPlayerWhileSoundPlaysIsDegradedAfterTenSeconds() async {
        let (service, perl, clock, monitor) = await running()
        await report(perl, pid: 0, nil)                                   // what a blocked helper says
        monitor.outputChanged(true)
        await settle()
        await clock.advance(by: .milliseconds(9_999))
        #expect(!monitor.isDegraded)
        await clock.advance(by: .milliseconds(1))
        #expect(monitor.isDegraded)
        #expect(service.diagnostics["media.degraded"] == "true")

        await report(perl, pid: 812, bundleID: "com.apple.Music", Fixtures.track("A"))   // a player appears
        #expect(!monitor.isDegraded)
        await report(perl, pid: 0, nil)
        monitor.outputChanged(false)                                      // the sound stopped first
        await clock.advance(by: .seconds(60))
        #expect(!monitor.isDegraded)
    }

    @Test("Sessions hidden by a filter prove the helper works", arguments: ["ignored", "browser"])
    func filteredSessionsAreNotSuspicious(_ filter: String) async {
        let services = CrannyServices.preview()
        if filter == "ignored" {
            services.settings[MediaSettings.ignoredBundleIDs] = ["com.spotify.client"]
        } else {
            services.settings[MediaSettings.showsBrowserMedia] = false
        }
        let (service, perl, clock, monitor) = await running(services: services)
        let bundleID = filter == "ignored" ? "com.spotify.client" : "com.google.Chrome"
        await report(perl, pid: 4242, bundleID: bundleID, Fixtures.track("Song", bundleID: bundleID))
        #expect(service.nowPlaying == nil)                                // hidden in the UI
        monitor.outputChanged(true)
        await clock.advance(by: .seconds(60))
        #expect(!monitor.isDegraded)
    }

    @Test func untitledSessionsAreNotSuspicious() async {
        // Telegram voice notes and untagged audio: a player is elected, it just has no title.
        let (service, perl, clock, monitor) = await running()
        await report(perl, pid: 812, bundleID: "ru.keepcoder.Telegram", nil)
        #expect(service.nowPlaying == nil)
        monitor.outputChanged(true)
        await clock.advance(by: .seconds(60))
        #expect(!monitor.isDegraded)
    }

    @Test func onlyTheBridgeIsJudged() async {
        // The Apple Events fallback reports no elected player at all (unknown, not 0).
        let (service, script, clock, monitor) = await running(.appleScript)
        script.emit(.nowPlaying(nil))
        await settle()
        #expect(service.reportedPlayerPID == nil)
        monitor.outputChanged(true)
        await clock.advance(by: .seconds(60))
        #expect(!monitor.isDegraded)
    }
}

@Suite("Apple Events fallback payloads") struct ScriptablePlayerTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func musicPayload() throws {
        let info = ["Name": "Midnight Window", "Artist": "The Example Band", "Album": "Night Signals",
                    "Total Time": "215000", "Player State": "Playing", "PersistentID": "6202394711290553447"]
        let np = try #require(ScriptablePlayer.music.nowPlaying(info, now: now))
        #expect(np.bundleID == "com.apple.Music")
        #expect(np.title == "Midnight Window")
        #expect(np.artist == "The Example Band")
        #expect(np.album == "Night Signals")
        #expect(np.duration == 215)                                       // milliseconds → seconds
        #expect(np.isPlaying)
        #expect(np.itemID == "6202394711290553447")
        #expect(np.elapsed == 0)
        #expect(!ScriptablePlayer.music.reportsPosition(info))            // Music needs a `player position` script
    }

    @Test func spotifyPayload() throws {
        let info = ["Name": "Midnight Window", "Artist": "The Example Band", "Album": "Night Signals", "Duration": "215000",
                    "Player State": "Paused", "Playback Position": "84.5", "Track ID": "spotify:track:42"]
        let np = try #require(ScriptablePlayer.spotify.nowPlaying(info, now: now))
        #expect(np.bundleID == "com.spotify.client")
        #expect(np.duration == 215)
        #expect(np.elapsed == 84.5)
        #expect(!np.isPlaying)
        #expect(np.itemID == "spotify:track:42")
        #expect(np.timestamp == now)
        #expect(ScriptablePlayer.spotify.reportsPosition(info))           // no script needed
    }

    @Test("Stopped or untitled is nothing playing", arguments: [
        ["Player State": "Stopped", "Name": "Song"],
        ["Player State": "Playing"],
        ["Player State": "Playing", "Name": ""],
        ["Name": "Song"],
    ])
    func stoppedOrUntitled(_ info: [String: String]) {
        #expect(ScriptablePlayer.music.nowPlaying(info, now: now) == nil)
    }

    @Test func zeroOrMissingDurationIsUnknown() throws {
        let zero = try #require(ScriptablePlayer.music.nowPlaying(["Name": "Radio", "Player State": "Playing", "Total Time": "0"], now: now))
        #expect(zero.duration == nil)
        let missing = try #require(ScriptablePlayer.spotify.nowPlaying(["Name": "Radio", "Player State": "Playing"], now: now))
        #expect(missing.duration == nil)
        #expect(missing.trackKey == "com.spotify.client|Radio||")
    }
}
