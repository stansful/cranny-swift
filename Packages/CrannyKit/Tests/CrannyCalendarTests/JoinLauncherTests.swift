import Foundation
import Testing
@testable import CrannyCalendar

/// "Join launches Zoom natively when installed, else the browser" (ARCHITECTURE.md §10.3). Nothing is ever
/// opened for real: `RecordingOpener` stands in for NSWorkspace.
@Suite @MainActor struct JoinLauncherTests {
    private func link(_ raw: String) throws -> MeetingLink {
        let url = try #require(URL(string: raw))
        return try #require(MeetingLinkDetector.classify(url))
    }

    @Test func zoomOpensInTheAppWhenInstalled() throws {
        let opener = RecordingOpener()
        opener.installedSchemes = ["zoommtg"]
        let outcome = JoinLauncher(opener: opener, joinsInApp: { true }).join(try link("https://acme.zoom.us/j/81234567890?pwd=s3cr3t"))
        let expected = try #require(URL(string: "zoommtg://acme.zoom.us/join?action=join&confno=81234567890&pwd=s3cr3t"))
        #expect(outcome == .app(expected))
        #expect(opener.opened == [expected])
    }

    @Test func zoomFallsBackToTheBrowser() throws {
        let opener = RecordingOpener()                                 // Zoom not installed
        let web = "https://acme.zoom.us/j/81234567890?pwd=s3cr3t"
        let outcome = JoinLauncher(opener: opener, joinsInApp: { true }).join(try link(web))
        #expect(outcome == .browser(try #require(URL(string: web))))
        #expect(opener.opened.map(\.absoluteString) == [web])
    }

    @Test func browserWhenTheUserPrefersIt() throws {
        let opener = RecordingOpener()
        opener.installedSchemes = ["zoommtg", "msteams"]
        let launcher = JoinLauncher(opener: opener, joinsInApp: { false })
        #expect(launcher.join(try link("https://zoom.us/j/1")) == .browser(try #require(URL(string: "https://zoom.us/j/1"))))
        #expect(opener.opened.allSatisfy { $0.scheme == "https" })
    }

    @Test func teamsMeetupJoinUsesTheTeamsScheme() throws {
        let raw = "https://teams.microsoft.com/l/meetup-join/19%3ameeting_ABC%40thread.v2/0?context=x"
        let outcome = JoinLauncher.plan(try link(raw), joinsInApp: true, hasApp: { $0.scheme == "msteams" })
        #expect(outcome == .app(try #require(URL(string: "msteams:/l/meetup-join/19%3ameeting_ABC%40thread.v2/0?context=x"))))
    }

    @Test func servicesWithoutAnAppSchemeUseTheBrowser() throws {
        let meet = try link("https://meet.google.com/abc-defg-hij")
        #expect(JoinLauncher.plan(meet, joinsInApp: true, hasApp: { _ in true }) == .browser(meet.url))
        let vanity = try link("https://zoom.us/my/jane")                // no meeting number: the web page hands off
        #expect(JoinLauncher.plan(vanity, joinsInApp: true, hasApp: { _ in true }) == .browser(vanity.url))
    }

    @Test func nativeOnlyLinksConvertBackToTheWeb() throws {
        let native = try link("zoommtg://zoom.us/join?action=join&confno=42&pwd=p")
        #expect(JoinLauncher.plan(native, joinsInApp: true, hasApp: { _ in true }) == .app(native.url))
        #expect(JoinLauncher.plan(native, joinsInApp: true, hasApp: { _ in false })
                == .browser(try #require(URL(string: "https://zoom.us/j/42?pwd=p"))))
        let teams = try link("msteams:/l/meetup-join/19%3ameeting_Y%40thread.v2/0")
        #expect(JoinLauncher.plan(teams, joinsInApp: false, hasApp: { _ in false })
                == .browser(try #require(URL(string: "https://teams.microsoft.com/l/meetup-join/19%3ameeting_Y%40thread.v2/0"))))
    }

    @Test func theZoomWebFallbackStaysOnZoom() throws {
        // The detector refuses foreign hosts; the conversion pins the host on its own as well (defence in depth).
        let crafted = MeetingLink(service: .zoom, url: try #require(URL(string: "zoommtg://zoom-login.evil.example/join?action=join&confno=8125550100&pwd=x")))
        #expect(MeetingLinkDetector.classify(crafted.url) == nil)
        #expect(JoinLauncher.plan(crafted, joinsInApp: true, hasApp: { _ in false })
                == .browser(try #require(URL(string: "https://zoom.us/j/8125550100?pwd=x"))))
        let gov = try link("zoommtg://acme.zoomgov.com/join?confno=7")
        #expect(JoinLauncher.plan(gov, joinsInApp: false, hasApp: { _ in false })
                == .browser(try #require(URL(string: "https://acme.zoomgov.com/j/7"))))
        // A meeting number that is not a number cannot reshape the path.
        let path = try link("zoommtg://zoom.us/join?confno=..%2F..%2Fsignin")
        #expect(JoinLauncher.plan(path, joinsInApp: true, hasApp: { _ in false }) == .failed)
    }

    @Test func failedOpenIsReported() throws {
        let opener = RecordingOpener()
        opener.opens = false
        #expect(JoinLauncher(opener: opener, joinsInApp: { true }).join(try link("https://zoom.us/j/1")) == .failed)
    }
}
