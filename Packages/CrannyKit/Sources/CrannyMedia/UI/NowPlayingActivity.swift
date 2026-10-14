// CrannyMedia/UI/NowPlayingActivity.swift — the Now Playing live activity (DESIGN.md §9.2, ARCHITECTURE.md §6.7):
// slot `.short`; artwork 20u leading, 5-bar visualizer trailing; P2 while playing, P3 paused; hidden after
// `hidePausedAfterSeconds` of pause (one sleep, no polling) and back on resume; `revision` = new tracks (the
// shell peeks on change); album palette for the light; swipes → previous/next.
import CrannyCore
import Foundation
import Observation
import SwiftUI

@MainActor @Observable final class NowPlayingActivity: LiveActivity {
    static let kind = ActivityKind(id: .nowPlaying, module: .media, title: MediaStrings.nowPlayingTitle, symbol: "music.note",
                                   defaultPriority: .ongoing, canPeekOnChange: true, peeksOnChangeByDefault: true)

    let id: ActivityID = .nowPlaying
    let slot: SlotWidth = .short
    @ObservationIgnored let service: MediaService
    @ObservationIgnored private let settings: SettingsStore
    @ObservationIgnored private let open: @MainActor (String) -> Void
    /// The pause outlasted `hidePausedAfterSeconds`.
    private var pauseExpired = false
    @ObservationIgnored private var pauseTimer: Task<Void, Never>?
    @ObservationIgnored private var tokens: [ObservationToken] = []

    /// `open(bundleID)` brings the player to the front (VoiceOver "Open in …").
    init(service: MediaService, settings: SettingsStore, open: @escaping @MainActor (String) -> Void = PlayerApps.open) {
        self.service = service
        self.settings = settings
        self.open = open
        tokens.append(observe({ [weak self] in self?.pauseState ?? PauseState() }) { [weak self] state in self?.pauseChanged(state) })
        pauseChanged(pauseState)
    }

    // MARK: LiveActivity

    var isActive: Bool { service.nowPlaying != nil && !pauseExpired }
    var priority: ActivityPriority { service.nowPlaying?.isPlaying == true ? .ongoing : .passive }
    var revision: Int { service.trackChangeCount }
    var palette: AmbientPalette? { service.palette }
    var opensWidget: WidgetID? { .media }
    var middleLabel: String? { service.nowPlaying?.title }

    var accessibilityLabel: String {
        guard let np = service.nowPlaying else { return MediaStrings.nothingPlaying }
        return MediaStrings.nowPlayingLabel(title: np.title, artist: np.artist)
    }

    var accessibilityValue: String? {
        guard let np = service.nowPlaying else { return nil }
        guard np.isPlaying else { return MediaStrings.paused }
        guard let duration = np.duration else { return MediaStrings.live }
        return MediaStrings.timeLeft(duration - np.position(at: service.clock.now))
    }

    var actions: [ActivityAction] {
        guard let np = service.nowPlaying else { return [] }
        let service = service
        var actions = [
            ActivityAction(id: "playPause", title: np.isPlaying ? MediaStrings.pause : MediaStrings.play,
                           symbol: np.isPlaying ? "pause.fill" : "play.fill") { Task { await service.send(.togglePlayPause) } },
            ActivityAction(id: "next", title: MediaStrings.nextTrack, symbol: "forward.fill") { Task { await service.send(.nextTrack) } },
            ActivityAction(id: "previous", title: MediaStrings.previousTrack, symbol: "backward.fill") { Task { await service.send(.previousTrack) } },
        ]
        if let source = np.bundleID ?? np.parentBundleID {
            let open = open
            actions.append(ActivityAction(id: "open", title: MediaStrings.openIn(PlayerApps.name(for: source, fallback: np.appName))) { open(source) })
        }
        return actions
    }

    /// Two-finger swipe over compact or peek (the shell checks Settings ▸ Gestures ▸ Swipe sideways).
    /// The gesture is the physical direction; Media applies Gestures ▸ Invert.
    func handle(_ gesture: ActivityGesture) -> Bool {
        guard service.nowPlaying != nil, service.supportsCommands, settings[CoreSettings.trackSwipe] else { return false }
        let next = (gesture == .swipeLeft) != settings[CoreSettings.invertTrackSwipe]
        let service = service
        Task { await service.send(next ? .nextTrack : .previousTrack) }
        return true
    }

    func compactLeading() -> some View { NowPlayingLeading(activity: self) }
    func compactTrailing() -> some View { NowPlayingTrailing(activity: self) }
    func minimal() -> some View { NowPlayingMinimal(activity: self) }
    func peekRow() -> some View { NowPlayingPeekRow(activity: self) }

    // MARK: Paused timeout

    private struct PauseState: Equatable {
        var hasSession = false
        var playing = false
        var trackKey: String?
        var timeout: Double = 0
    }

    private var pauseState: PauseState {
        PauseState(hasSession: service.nowPlaying != nil, playing: service.nowPlaying?.isPlaying ?? false,
                   trackKey: service.nowPlaying?.trackKey, timeout: settings[MediaSettings.hidePausedAfterSeconds])
    }

    private func pauseChanged(_ state: PauseState) {
        pauseTimer?.cancel(); pauseTimer = nil
        guard state.hasSession, !state.playing, state.timeout > 0 else {
            if pauseExpired { pauseExpired = false }                  // resumed, new session, or "never"
            return
        }
        guard !pauseExpired else { return }
        let clock = service.clock
        pauseTimer = Task { [weak self] in
            do { try await clock.sleep(for: .seconds(state.timeout)) } catch { return }
            self?.pauseExpired = true
        }
    }
}
