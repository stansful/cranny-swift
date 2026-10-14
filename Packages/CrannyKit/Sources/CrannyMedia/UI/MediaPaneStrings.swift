// CrannyMedia/UI/MediaPaneStrings.swift — copy of Settings ▸ Media and of the Now Playing options row in
// Settings ▸ Live Activities (sentence case, calm, no exclamation marks; DESIGN.md §17).
import CrannyCore
import Foundation

enum MediaPaneStrings {
    // Rows
    static var source: String { String(localized: "Source", bundle: .module,
               comment: "Settings ▸ Media: section header for the media source") }
    static var noSource: String { String(localized: "No source", bundle: .module,
               comment: "Settings ▸ Media: source row label when no helper runs") }
    static var visualizer: String { String(localized: "Visualizer", bundle: .module,
               comment: "Settings ▸ Media: row label") }
    static var showBrowserMedia: String { String(localized: "Show media from browsers", bundle: .module,
               comment: "Settings ▸ Media: toggle") }
    static var ignoreApps: String { String(localized: "Ignore apps", bundle: .module,
               comment: "Settings ▸ Media: row label and file-picker button") }
    static var ignoreFootnote: String {
        String(localized: "macOS shares only the app it picked as now playing, so ignoring an app is the way to keep it out of the notch.", bundle: .module,
               comment: "Settings ▸ Media: footnote under Ignore apps")
    }
    static var add: String { String(localized: "Add", bundle: .module,
               comment: "Settings ▸ Media ▸ Ignore apps: menu button") }
    static var chooseApp: String { String(localized: "Choose an app…", bundle: .module,
               comment: "Settings ▸ Media ▸ Ignore apps: menu item that opens a file picker") }
    static var stopIgnoring: String { String(localized: "Stop ignoring", bundle: .module,
               comment: "Settings ▸ Media ▸ Ignore apps: remove button (tooltip, VoiceOver)") }
    static var artworkInCompact: String { String(localized: "Show artwork in the notch", bundle: .module,
               comment: "Settings ▸ Media: toggle (compact activity)") }
    static var peekOnTrackChange: String { String(localized: "Peek when the track changes", bundle: .module,
               comment: "Settings ▸ Media: toggle") }
    static var appleEvents: String { String(localized: "Apple Events fallback for Music and Spotify", bundle: .module,
               comment: "Settings ▸ Media: toggle") }
    static var appleEventsFootnote: String {
        String(localized: "Used only when the media helper can't run. macOS asks once per app whether Cranny may control it.", bundle: .module,
               comment: "Settings ▸ Media: footnote under the Apple Events fallback")
    }
    static var testDetection: String { String(localized: "Test media detection", bundle: .module,
               comment: "Settings ▸ Media: button") }
    static var resetToDefault: String { String(localized: "Reset to Default", bundle: .module,
               comment: "Settings ▸ Media: row context menu item") }

    // Status
    static var statusIdle: String { String(localized: "Not started", bundle: .module,
               comment: "Settings ▸ Media: source status") }
    static var statusStarting: String { String(localized: "Starting", bundle: .module,
               comment: "Settings ▸ Media: source status") }
    static var statusWorking: String { String(localized: "Working", bundle: .module,
               comment: "Settings ▸ Media: source status") }
    static var statusDegraded: String { String(localized: "Can't see the player", bundle: .module,
               comment: "Settings ▸ Media: source status when sound plays but nothing is detected") }
    static var statusRestarting: String { String(localized: "Restarting", bundle: .module,
               comment: "Settings ▸ Media: source status") }
    static var statusUnavailable: String { String(localized: "Not available", bundle: .module,
               comment: "Settings ▸ Media: source status") }
    static var degraded: String {
        String(localized: "Sound is playing, but the media helper reports nothing. Try the Apple Events fallback below.", bundle: .module,
               comment: "Settings ▸ Media: warning when the helper seems blocked")
    }

    // Test media detection
    static var testSample: String { String(localized: "Previews use a sample track.", bundle: .module,
               comment: "Settings ▸ Media: test result in a preview") }
    static var testNoHelper: String { String(localized: "The media helper isn't running.", bundle: .module,
               comment: "Settings ▸ Media: test result") }
    static var testNoAnswer: String { String(localized: "The media helper didn't answer.", bundle: .module,
               comment: "Settings ▸ Media: test result") }
    static func testSeesPlayer(_ app: String, _ milliseconds: Int) -> String {
        String(localized: "Working: the helper answered in \(milliseconds) ms and sees \(app).", bundle: .module,
               comment: "Settings ▸ Media: test result; arguments are a round-trip time in milliseconds and a player name")
    }
    static func testBlind(_ milliseconds: Int) -> String {
        String(localized: "The helper answered in \(milliseconds) ms, but sound is playing and it sees nothing. Try the Apple Events fallback.",
               bundle: .module, comment: "Settings ▸ Media: test result; argument is a round-trip time in milliseconds")
    }
    static func testIdle(_ milliseconds: Int) -> String {
        String(localized: "The helper answered in \(milliseconds) ms. Play something to check that it appears.", bundle: .module,
               comment: "Settings ▸ Media: test result when nothing plays; argument is a round-trip time in milliseconds")
    }

    // Live visualizer
    static var liveReceiving: String { allowed }
    static var liveWaiting: String { String(localized: "Starts when music plays", bundle: .module,
               comment: "Settings ▸ Media: System Audio Recording status for the Live visualizer") }
    static var liveSilent: String { String(localized: "No sound received", bundle: .module,
               comment: "Settings ▸ Media: System Audio Recording status for the Live visualizer") }
    static var liveDenied: String { String(localized: "Not allowed", bundle: .module,
               comment: "Settings ▸ Media: System Audio Recording status for the Live visualizer") }
    static var liveFailed: String { String(localized: "Can't start", bundle: .module,
               comment: "Settings ▸ Media: System Audio Recording status for the Live visualizer") }
    static var liveUnsupported: String { String(localized: "Needs macOS 14.2 or later", bundle: .module,
               comment: "Settings ▸ Media: System Audio Recording status for the Live visualizer") }
    static var liveSheetTitle: String { String(localized: "Use the Live visualizer?", bundle: .module,
               comment: "Settings ▸ Media: why-sheet title") }
    static var liveSheetBody: String {
        String(localized: "To move with the music, Cranny listens to the sound your Mac plays. macOS will ask you to allow System Audio Recording. Cranny never records, saves or sends any audio, and listens only while the visualizer is on screen.", bundle: .module,
               comment: "Settings ▸ Media: why-sheet text before the System Audio Recording prompt")
    }
    static var cancel: String { String(localized: "Cancel", bundle: .module,
               comment: "Settings ▸ Media: why-sheet button") }
    static var continueTitle: String { String(localized: "Continue", bundle: .module,
               comment: "Settings ▸ Media: why-sheet button") }
    static var openPrivacySettings: String { String(localized: "Open System Settings…", bundle: .module,
               comment: "Settings ▸ Media: button that opens Privacy & Security") }

    // Automation rows
    static var allowed: String { String(localized: "Allowed", bundle: .module,
               comment: "Settings ▸ Media: permission status (Automation for a player, System Audio Recording for Live)") }
    static var allow: String { String(localized: "Allow…", bundle: .module,
               comment: "Settings ▸ Media: button that asks for Automation permission") }
    static var notInstalled: String { String(localized: "Not installed", bundle: .module,
               comment: "Settings ▸ Media: Automation row of a player that is not installed") }
    static var openToAllow: String { String(localized: "Open the app to allow", bundle: .module,
               comment: "Settings ▸ Media: Automation row while the player is not running") }

    // Live Activities ▸ Now Playing options row
    static var hidePaused: String { String(localized: "Hide paused media", bundle: .module,
               comment: "Live Activities pane: Now Playing option, picker label") }
    static var never: String { String(localized: "Never", bundle: .module,
               comment: "Live Activities pane: Now Playing option, never hide paused media") }
    static func after(_ seconds: Double) -> String {
        let text = Duration.seconds(seconds).formatted(.units(allowed: [.minutes, .seconds], width: .wide))
        return String(localized: "After \(text)", bundle: .module,
                      comment: "Live Activities pane: Now Playing option; argument is a spelled-out duration (\"30 seconds\")")
    }

    /// Settings search: the pane's row labels (ARCHITECTURE.md §3.7).
    static var keywords: [String] {
        [source, visualizer, showBrowserMedia, ignoreApps, artworkInCompact, peekOnTrackChange, appleEvents, testDetection,
         String(localized: "music now playing player artwork spotify youtube", bundle: .module,
               comment: "Settings search: extra words for the Media pane, space-separated (translate each word)")]
    }
}
