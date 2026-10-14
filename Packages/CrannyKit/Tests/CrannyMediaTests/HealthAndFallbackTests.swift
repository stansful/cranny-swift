// The blocked-helper heuristic (R2 §5.4) with a manual clock and fed Core Audio state: only "no elected player
// (pid 0) while another process plays sound for 10 s" is degraded; filtered and untitled sessions are not.
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
