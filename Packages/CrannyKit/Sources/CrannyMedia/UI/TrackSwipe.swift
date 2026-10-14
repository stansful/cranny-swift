// CrannyMedia/UI/TrackSwipe.swift — the one rule for "two-finger swipe sideways changes the track" (DESIGN.md §4.4,
// Settings ▸ Gestures), shared by compact/peek (`NowPlayingActivity.handle`) and the Media widget's artwork and
// title: off when Swipe sideways to change track is off or the player cannot be controlled; Invert flips it.
// Directions are physical finger motion (the shell does not invert them).
import CrannyCore
import Foundation

@MainActor enum TrackSwipe {
    /// Whether a swipe may change the track right now (else: no rubber band, no command).
    static func isEnabled(settings: SettingsStore, service: MediaService) -> Bool {
        settings[CoreSettings.trackSwipe] && service.supportsCommands && service.nowPlaying != nil
    }

    /// The command for a committed swipe; nil when swipes are off or the direction is vertical.
    static func command(for direction: SwipeDirection, settings: SettingsStore, service: MediaService) -> MediaCommand? {
        guard isEnabled(settings: settings, service: service) else { return nil }
        let next: Bool
        switch direction {
        case .left: next = true
        case .right: next = false
        case .up, .down: return nil
        }
        return next != settings[CoreSettings.invertTrackSwipe] ? .nextTrack : .previousTrack
    }

    /// Compact and peek report swipes as `ActivityGesture`s.
    static func command(for gesture: ActivityGesture, settings: SettingsStore, service: MediaService) -> MediaCommand? {
        command(for: gesture == .swipeLeft ? .left : .right, settings: settings, service: service)
    }
}
