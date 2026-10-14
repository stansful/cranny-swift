// CrannyMedia/UI/MediaStrings.swift — copy shared by the widget, the Now Playing activity, ⌘K and VoiceOver, so
// each English key has exactly one translator comment (ARCHITECTURE.md §8.7, §10.0 strings scheme).
import CrannyCore
import Foundation

enum MediaStrings {
    static var moduleName: String {
        String(localized: "Media", bundle: .module, comment: "Media: module name (widget title, ⌘K result kind)")
    }
    static var nowPlayingTitle: String {
        String(localized: "Now Playing", bundle: .module, comment: "Live Activities pane: the media activity's name")
    }
    static var play: String { String(localized: "Play", bundle: .module, comment: "Media: transport button and VoiceOver action") }
    static var pause: String { String(localized: "Pause", bundle: .module, comment: "Media: transport button and VoiceOver action") }
    static var nextTrack: String { String(localized: "Next track", bundle: .module, comment: "Media: transport button and VoiceOver action") }
    static var previousTrack: String {
        String(localized: "Previous track", bundle: .module, comment: "Media: transport button and VoiceOver action")
    }
    static var shuffle: String { String(localized: "Shuffle", bundle: .module, comment: "Media widget: shuffle button (6 cells)") }
    static var shuffleOn: String { String(localized: "Shuffle on", bundle: .module, comment: "Media widget: shuffle button value for VoiceOver") }
    static var repeatMode: String { String(localized: "Repeat", bundle: .module, comment: "Media widget: repeat button (6 cells)") }
    static var repeatOne: String { String(localized: "Repeat one", bundle: .module, comment: "Media widget: repeat button value for VoiceOver") }
    static var repeatAll: String { String(localized: "Repeat all", bundle: .module, comment: "Media widget: repeat button value for VoiceOver") }
    static var off: String {
        String(localized: "Off", bundle: .module, comment: "Media: \"off\" state (shuffle/repeat VoiceOver value, Settings ▸ Media ▸ Visualizer segment)")
    }
    static var nothingPlaying: String {
        String(localized: "Nothing playing", bundle: .module, comment: "Media widget: empty state")
    }
    static var playbackPosition: String {
        String(localized: "Playback position", bundle: .module, comment: "Media widget: VoiceOver label of the scrubber")
    }
    static var live: String { String(localized: "Live", bundle: .module, comment: "Media: a live stream has no duration (VoiceOver value; shown uppercase in the widget)") }
    static var paused: String { String(localized: "Paused", bundle: .module, comment: "Media: VoiceOver value while playback is paused") }
    static var retry: String { String(localized: "Retry", bundle: .module, comment: "Media widget: error state button") }

    static func openIn(_ app: String) -> String {
        String(localized: "Open in \(app)", bundle: .module, comment: "Media: tooltip and VoiceOver action on the artwork; argument is the player's name")
    }

    /// "Now playing: Midnight Window by The Example Band" (DESIGN.md §16).
    static func nowPlayingLabel(title: String, artist: String?) -> String {
        if let artist {
            String(localized: "Now playing: \(title) by \(artist)", bundle: .module, comment: "Media: VoiceOver label; arguments are the track title and the artist")
        } else {
            String(localized: "Now playing: \(title)", bundle: .module, comment: "Media: VoiceOver label; argument is the track title")
        }
    }

    /// "2 minutes 11 seconds left".
    static func timeLeft(_ seconds: TimeInterval) -> String {
        let text = Duration.seconds(max(seconds, 0).rounded())
            .formatted(.units(allowed: [.hours, .minutes, .seconds], width: .wide))
        return String(localized: "\(text) left", bundle: .module, comment: "Media: VoiceOver value; argument is a spelled-out duration (\"2 minutes 11 seconds\")")
    }

    /// "1:24" for the widget's time labels (hours only when needed).
    static func clock(_ seconds: TimeInterval) -> String {
        let s = max(seconds, 0)
        let pattern: Duration.TimeFormatStyle.Pattern = s >= 3600 ? .hourMinuteSecond : .minuteSecond
        return Duration.seconds(s.rounded(.down)).formatted(.time(pattern: pattern))
    }
}
