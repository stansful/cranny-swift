import CrannyCore
import Foundation
import Testing
@testable import CrannyCalendar

/// ARCHITECTURE.md §10.3: R3's twelve cases plus more Teams, Webex, SafeLinks and redirect variants.
@Suite struct MeetingLinkDetectorTests {
    private func first(url: String? = nil, location: String? = nil, notes: String? = nil) -> MeetingLink? {
        MeetingLinkDetector.links(url: url.flatMap(URL.init(string:)), location: location, notes: notes).first
    }

    // MARK: - The twelve core cases

    @Test func zoomInLocation() {
        let link = first(location: "https://us02web.zoom.us/j/81234567890?pwd=abcDEF")
        #expect(link?.service == .zoom)
        #expect(link?.url.absoluteString == "https://us02web.zoom.us/j/81234567890?pwd=abcDEF")
    }

    @Test func zoomGovAndVanity() {
        #expect(first(notes: "Join: https://acme.zoomgov.com/j/1601234567")?.service == .zoom)
        #expect(first(notes: "https://acme.zoom.us/my/jane.doe")?.service == .zoom)
        #expect(first(notes: "Webinar https://zoom.us/w/99887766?tk=x")?.service == .zoom)
    }

    @Test func zoomNativeScheme() {
        #expect(first(location: "zoommtg://zoom.us/join?action=join&confno=123456789")?.service == .zoom)
    }

    @Test func googleMeetCodeInNotes() {
        let link = first(notes: "Video call link: https://meet.google.com/abc-defg-hij\nOr dial: +1 555-0100 PIN: 123#")
        #expect(link?.service == .meet)
        #expect(link?.url.absoluteString == "https://meet.google.com/abc-defg-hij")
    }

    @Test func googleMeetLookup() {
        #expect(first(notes: "https://meet.google.com/lookup/abcdefghij?authuser=0")?.service == .meet)
    }

    @Test func teamsMeetupJoin() {
        let raw = "https://teams.microsoft.com/l/meetup-join/19%3ameeting_ABC%40thread.v2/0?context=%7b%22Tid%22%3a%22x%22%7d"
        let link = first(notes: "Microsoft Teams meeting\nJoin on your computer: \(raw)")
        #expect(link?.service == .teams)
        #expect(link?.url.absoluteString == raw)
    }

    @Test func teamsNewShortLink() {
        #expect(first(notes: "Join: https://teams.microsoft.com/meet/2345678901234?p=AbCdEfGh")?.service == .teams)
        #expect(first(notes: "https://teams.live.com/meet/9876543210?p=xyz")?.service == .teams)
        #expect(first(notes: "https://teams.cloud.microsoft/meet/2345678901234?p=Q")?.service == .teams)
    }

    @Test func teamsInOutlookSafeLinks() {
        let wrapped = "https://nam12.safelinks.protection.outlook.com/?url=https%3A%2F%2Fteams.microsoft.com%2Fl%2Fmeetup-join%2F19%253ameeting_X%2540thread.v2%2F0&data=05%7C01%7C&sdata=abc&reserved=0"
        let link = first(notes: "Click here to join the meeting <\(wrapped)>")
        #expect(link?.service == .teams)
        #expect(link?.url.host == "teams.microsoft.com")
        #expect(link?.url.absoluteString.hasPrefix("https://teams.microsoft.com/l/meetup-join/19%3ameeting_X%40thread.v2/0") == true)
    }

    @Test func webexMeetingLink() {
        #expect(first(location: "https://acme.webex.com/acme/j.php?MTID=m0123456789abcdef")?.service == .webex)
    }

    @Test func faceTimeLink() {
        #expect(first(url: "https://facetime.apple.com/join#v=1&p=AbCd&k=EfGh")?.service == .facetime)
    }

    @Test func slackHuddle() {
        #expect(first(notes: "Huddle: https://app.slack.com/huddle/T01234567/C07654321")?.service == .slack)
    }

    @Test func searchOrderIsURLThenLocationThenNotesAndEarliestWins() {
        let links = MeetingLinkDetector.links(
            url: URL(string: "https://acme.webex.com/meet/jdoe"),
            location: "Room 4; https://meet.google.com/abc-defg-hij",
            notes: "Zoom: https://zoom.us/j/111 or Teams https://teams.microsoft.com/meet/222?p=a")
        #expect(links.map(\.service) == [.webex, .meet, .zoom, .teams])
        // Within one field the earliest link wins even when a later one looks "more official".
        #expect(first(notes: "Backup https://meet.google.com/xyz-abcd-efg — main https://zoom.us/j/1")?.service == .meet)
    }

    // MARK: - More variants

    @Test func teamsVariants() {
        #expect(first(notes: "msteams:/l/meetup-join/19%3ameeting_Y%40thread.v2/0?context=x")?.service == .teams)
        #expect(first(notes: "https://gov.teams.microsoft.us/l/meetup-join/19%3ameeting_Z%40thread.v2/0")?.service == .teams)
        #expect(first(notes: "https://dod.teams.microsoft.us/l/meetup-join/19%3ameeting_Z%40thread.v2/0")?.service == .teams)
        let teamsSafeLinksPage = "https://statics.teams.cdn.office.net/evergreen-assets/safelinks/1/atp-safelinks.html?url=https%3A%2F%2Fteams.microsoft.com%2Fmeet%2F123%3Fp%3Dabc&locale=en-us"
        #expect(first(notes: teamsSafeLinksPage)?.url.absoluteString == "https://teams.microsoft.com/meet/123?p=abc")
    }

    @Test func webexVariants() {
        #expect(first(notes: "https://acme.webex.com/meet/jdoe")?.service == .webex)
        #expect(first(notes: "https://acme.webex.com/join/jdoe")?.service == .webex)
        #expect(first(notes: "https://acme.webex.com/wbxmjs/joinservice/sites/acme/meeting/download/abc")?.service == .webex)
        #expect(first(notes: "https://www.webex.com/downloads.html") == nil)
    }

    @Test func googleRedirectAndNestedWrappers() {
        #expect(first(notes: "https://www.google.com/url?q=https://meet.google.com/abc-defg-hij&sa=D&source=calendar")?.service == .meet)
        let nested = "https://www.google.com/url?q=" + "https://eur01.safelinks.protection.outlook.com/?url=https%3A%2F%2Fzoom.us%2Fj%2F42%3Fpwd%3Dx&data=1"
            .addingPercentEncoding(withAllowedCharacters: .alphanumerics)!
        let link = first(notes: nested)
        #expect(link?.service == .zoom)
        #expect(link?.url.absoluteString == "https://zoom.us/j/42?pwd=x")
    }

    @Test func proofpointURLDefense() {
        #expect(first(notes: "https://urldefense.com/v3/__https://zoom.us/j/777?pwd=q__;!!ABC!def$")?.url.absoluteString == "https://zoom.us/j/777?pwd=q")
        #expect(first(notes: "https://urldefense.proofpoint.com/v2/url?u=https-3A__meet.google.com_abc-2Ddefg-2Dhij&d=DwMF")?.service == .meet)
    }

    @Test func htmlNotesAndPunctuation() {
        let html = #"<p>Join <a href="https://zoom.us/j/123?pwd=a&amp;uname=b">here</a>.</p>"#
        #expect(first(notes: html)?.url.absoluteString == "https://zoom.us/j/123?pwd=a&uname=b")
        #expect(first(notes: "Link: https://meet.google.com/abc-defg-hij.")?.url.absoluteString == "https://meet.google.com/abc-defg-hij")
        #expect(first(notes: "(https://zoom.us/j/5)")?.url.absoluteString == "https://zoom.us/j/5")
    }

    @Test func otherServices() {
        #expect(first(notes: "https://whereby.com/team-room")?.service == .whereby)
        #expect(first(notes: "https://whereby.com/information") == nil)
        #expect(first(notes: "https://meet.goto.com/123456789")?.service == .goto)
        #expect(first(notes: "https://global.gotomeeting.com/join/123456789")?.service == .goto)
        #expect(first(notes: "https://meet.jit.si/CrannyStandup")?.service == .jitsi)
        #expect(first(notes: "https://chime.aws/1234567890")?.service == .chime)
        #expect(first(notes: "https://app.chime.aws/meetings/1234567890")?.service == .chime)
    }

    @Test func nonMeetingLinksAreIgnored() {
        for text in ["https://zoom.us/download", "https://meet.google.com/", "https://meet.google.com/landing",
                     "https://teams.microsoft.com/l/channel/19%3aabc/General", "https://example.com/j/123",
                     "https://facetime.apple.com/", "https://app.slack.com/client/T1/C2", "mailto:a@example.com",
                     "no links here at all", "https://zoom.us.example.com/j/1"] {
            #expect(first(notes: text) == nil, "\(text)")
        }
    }

    @Test func duplicatesAreDropped() {
        let links = MeetingLinkDetector.links(url: URL(string: "https://zoom.us/j/1"), location: "https://zoom.us/j/1",
                                              notes: "https://zoom.us/j/1 https://zoom.us/j/1")
        #expect(links.count == 1)
    }

    @Test func allowedServicesFilterTheJoinLink() {
        let event = EventSnapshot(id: "e", title: "t", start: .now, end: .now, calendarID: "c", color: .white,
                                  links: MeetingLinkDetector.links(url: nil, location: "https://zoom.us/j/1",
                                                                   notes: "https://meet.google.com/abc-defg-hij"))
        #expect(event.link(allowing: Set(MeetingService.allCases))?.service == .zoom)
        #expect(event.link(allowing: [.meet, .teams])?.service == .meet)
        #expect(event.link(allowing: [.teams]) == nil)
    }

    @Test func readableLocationDropsURLs() {
        func location(_ text: String?) -> String? {
            EventSnapshot(id: "e", title: "t", start: .now, end: .now, calendarID: "c", color: .white, location: text).readableLocation
        }
        #expect(location("Room 4; https://zoom.us/j/1") == "Room 4")
        #expect(location("https://zoom.us/j/1") == nil)
        #expect(location("Microsoft Teams Meeting") == "Microsoft Teams Meeting")
        #expect(location("  ") == nil)
        #expect(location(nil) == nil)
    }
}
