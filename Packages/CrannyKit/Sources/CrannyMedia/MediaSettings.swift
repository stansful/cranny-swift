// CrannyMedia/MediaSettings.swift — the module's settings keys (namespace `media.`, ARCHITECTURE.md §10.2).
// Never rename a key or change its type: add a new key and migrate in `onLaunch`.
import CrannyCore
import Foundation

/// Settings ▸ Media ▸ Visualizer (DESIGN.md §5.3, §9.2; ARCHITECTURE.md §6.6).
public nonisolated enum MediaVisualizerMode: String, CaseIterable, Codable, Sendable {
    /// Real levels from a Core Audio process tap (macOS 14.2+; asks for System Audio Recording).
    case live
    /// An honest breathing pattern derived from the track, not from the audio (default, no permission).
    case ambient
    /// Static dots: shows that something plays, never moves.
    case `static`
    /// No visualizer anywhere.
    case off
}

/// Every key the Media module owns (Settings ▸ Media, the Now Playing options row, the widget options).
public nonisolated enum MediaSettings {
    /// Visualizer mode in compact, peek and the widget. `.live` needs System Audio Recording.
    public static let visualizer = SettingKey<MediaVisualizerMode>(.media, "visualizer", default: .ambient)
    /// Fall back to Apple Events for Music and Spotify when the MediaRemote helper is unavailable
    /// (asks for Automation permission per app, so it is off by default).
    public static let allowAppleEvents = SettingKey<Bool>(.media, "allowAppleEvents", default: false)
    /// Players whose sessions are never shown (bundle identifiers). The only "source" control: macOS
    /// exposes just the system's current now-playing app, so there is no source priority (R2 §9.6).
    public static let ignoredBundleIDs = SettingKey<[String]>(.media, "ignoredBundleIDs", default: [])
    /// Show sessions that come from web browsers (YouTube, web players).
    public static let showsBrowserMedia = SettingKey<Bool>(.media, "showsBrowserMedia", default: true)
    /// Album artwork in the compact leading slot (otherwise a note glyph).
    public static let artworkInCompact = SettingKey<Bool>(.media, "artworkInCompact", default: true)
    /// Seconds a paused session stays in the notch before Now Playing hides; 0 = never hide.
    /// It comes back as soon as playback resumes.
    public static let hidePausedAfterSeconds = SettingKey<Double>(.media, "hidePausedAfterSeconds", default: 30)
    /// The small visualizer next to the artist in the Media widget.
    public static let showsVisualizerInWidget = SettingKey<Bool>(.media, "showsVisualizerInWidget", default: true)

    /// Choices offered for `hidePausedAfterSeconds` (0 = never).
    static let hidePausedChoices: [Double] = [10, 30, 60, 300, 0]
}
