// CrannyMedia/UI/MediaPlayingView.swift — the Media widget with a session (DESIGN.md §7.1):
//   5 cells: [artwork 96 r 8 + album glow] [title ⌁ · artist ▮▮▮ · scrubber · 1:24 … −2:11 · ⏮ (⏸) ⏭]
//   4 cells: [artwork 72] [title · artist · ⏮ (⏸) ⏭] over an inline "1:24 ━━━ −2:11" row
//   6 cells: 5 + shuffle and repeat around the transport.
// Click the artwork to open the player; a two-finger swipe over the artwork or title changes the track (`TrackSwipe`:
// Settings ▸ Gestures ▸ Swipe sideways and Invert); the title marquees after a 1.5-s hover (never under Reduce
// Motion). Transport, swipes and VoiceOver transport actions only when the source can control the player.
import CrannyCore
import SwiftUI

struct MediaPlayingView: View {
    @Environment(\.cranny) private var theme
    @State private var swipe: CGFloat = 0
    @State private var marquee = false
    @State private var hoverTask: Task<Void, Never>?
    let service: MediaService
    let nowPlaying: NowPlaying
    let context: WidgetContext
    let haptics: Haptics?
    let settings: SettingsStore

    var body: some View {
        let compact = context.cells <= 4
        let height = context.contentSize.height
        let artSize = compact ? max(height - HitTarget.nook.height, 0) : height
        Group {
            if compact {
                VStack(spacing: 0) {
                    HStack(alignment: .top, spacing: Space.l) {
                        artwork(size: artSize)
                        VStack(alignment: .leading, spacing: 0) {
                            titleBlock(showsRoute: false)
                            Spacer(minLength: 0)
                            if service.supportsCommands {
                                TransportControls(service: service, spacing: Space.xs).padding(.leading, -Space.xs)
                            }
                        }
                        .frame(height: artSize)
                    }
                    MediaProgress(service: service, style: .inline, haptics: haptics)
                        .frame(height: HitTarget.nook.height)
                }
            } else {
                HStack(alignment: .top, spacing: Space.l) {
                    artwork(size: artSize)
                    VStack(alignment: .leading, spacing: 0) {
                        titleBlock(showsRoute: true)
                        MediaProgress(service: service, haptics: haptics)
                        Spacer(minLength: 0)
                        if service.supportsCommands {
                            TransportControls(service: service, showsModes: context.cells >= 6)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .frame(height: artSize)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    // MARK: Pieces

    private func artwork(size: CGFloat) -> some View {
        let source = nowPlaying.bundleID ?? nowPlaying.parentBundleID
        let appName = source.flatMap { PlayerApps.name(for: $0, fallback: nowPlaying.appName) } ?? nowPlaying.appName
        return Button { if let source { PlayerApps.open(source) } } label: {
            ArtworkView(image: service.artwork, identity: service.artworkKey, size: size,
                        radius: theme.grid.innerRadius, glows: settings[CoreSettings.albumGlow], accent: service.palette?.accent)
                .notchMatched(MatchedID.mediaArtwork)
        }
        .buttonStyle(.plain)
        .disabled(source == nil)
        .help(source == nil ? "" : MediaStrings.openAction(appName))
        .accessibilityLabel(Text(verbatim: source == nil ? MediaStrings.moduleName : MediaStrings.openAction(appName)))
        .crannyPhysicalOffset(x: swipe)                     // follows the fingers, also right to left
        .crannyScrollZone(ScrollZoneID("media.track.artwork"), axis: .horizontal, onUpdate: trackSwipe)
    }

    private func titleBlock(showsRoute: Bool) -> some View {
        let showsBars = settings[MediaSettings.showsVisualizerInWidget] && !context.isEditingLayout
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Space.xs) {
                // At rest: one line with tail truncation (DESIGN.md §2.2). After a 1.5-s hover the overflowing title
                // marquees once over the same box (never under Reduce Motion; the tooltip shows it instead).
                Text(verbatim: nowPlaying.title)
                    .crannyFont(.title).lineLimit(1).truncationMode(.tail)
                    .opacity(marquee && !theme.reduceMotion ? 0 : 1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(alignment: .leading) {
                        MarqueeText(nowPlaying.title, style: .title, isActive: marquee)
                            .opacity(marquee && !theme.reduceMotion ? 1 : 0)
                    }
                    .clipped()
                    .help(nowPlaying.title)
                    .foregroundStyle(theme.palette.label)
                if showsRoute {
                    OutputDeviceMenu().padding(.vertical, -Space.xs).padding(.trailing, -Space.s).layoutPriority(1)
                }
            }
            HStack(spacing: Space.s) {
                Text(verbatim: nowPlaying.artist ?? nowPlaying.album ?? nowPlaying.appName ?? "")
                    .crannyFont(.callout).foregroundStyle(theme.palette.secondaryLabel)
                    .lineLimit(1).truncationMode(.tail)
                Spacer(minLength: 0)
                if showsBars {
                    VisualizerBars(engine: service.visualizer, isPlaying: nowPlaying.isPlaying,
                                   trackKey: nowPlaying.trackKey, metrics: .widget, feedsLight: true)
                }
            }
        }
        .crannyPhysicalOffset(x: swipe * 0.6)
        .contentShape(Rectangle())
        .onHover(perform: hoverTitle)
        .crannyScrollZone(ScrollZoneID("media.track.title"), axis: .horizontal, onUpdate: trackSwipe)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: MediaStrings.nowPlayingLabel(title: nowPlaying.title, artist: nowPlaying.artist)))
        .accessibilityValue(Text(verbatim: nowPlaying.isPlaying ? "" : MediaStrings.paused))
        .accessibilityActions {
            if service.supportsCommands {
                Button { Task { await service.send(.togglePlayPause) } } label: {
                    Text(verbatim: nowPlaying.isPlaying ? MediaStrings.pause : MediaStrings.play)
                }
                Button { Task { await service.send(.nextTrack) } } label: { Text(verbatim: MediaStrings.nextTrack) }
                Button { Task { await service.send(.previousTrack) } } label: { Text(verbatim: MediaStrings.previousTrack) }
            }
        }
    }

    // MARK: Interaction

    /// The single marquee: after 1.5 s of hover (the caller owns the timer, DESIGN.md §2.2).
    private func hoverTitle(_ hovering: Bool) {
        hoverTask?.cancel()
        guard hovering else { marquee = false; return }
        hoverTask = Task {
            try? await Task.sleep(for: .milliseconds(1500))
            if !Task.isCancelled { marquee = true }
        }
    }

    /// Two-finger horizontal swipe (DESIGN.md §4.4): rubber-band, then next/previous with an `.alignment` haptic.
    /// With Swipe sideways to change track off (or a read-only source) the content does not move at all.
    private func trackSwipe(_ update: SwipeUpdate) {
        guard TrackSwipe.isEnabled(settings: settings, service: service) else {
            if swipe != 0 { withAnimation(theme.animation(.snapBack)) { swipe = 0 } }
            return
        }
        switch update {
        case .tracking(_, let translation):
            swipe = CrannyMotion.rubberBand(translation, limit: GestureSpec.horizontalTravel)
        case .committed(let direction, _):
            guard let command = TrackSwipe.command(for: direction, settings: settings, service: service) else {
                withAnimation(theme.animation(.snapBack)) { swipe = 0 }
                return
            }
            haptics?.play(.alignment)
            withAnimation(theme.animation(.contentOut)) {
                swipe = command == .nextTrack ? -GestureSpec.horizontalTravel : GestureSpec.horizontalTravel
            }
            Task {
                await service.send(command)
                withAnimation(theme.animation(.snapBack)) { swipe = 0 }
            }
        case .cancelled:
            withAnimation(theme.animation(.snapBack)) { swipe = 0 }
        }
    }
}

#Preview("Playing · 5 cells, long title") {
    let service = SampleMedia.previewService()
    var np = SampleMedia.nowPlaying()
    np.title = "An unusually long title that needs the marquee"
    return MediaPlayingView(service: service, nowPlaying: np,
                            context: WidgetContext(cells: 5, contentSize: CGSize(width: 288, height: 96)),
                            haptics: nil, settings: service.settings)
        .frame(width: 288, height: 96)
        .crannyCard(cells: 5)
        .padding(Space.xxl)
        .background(.black)
        .crannyThemeRoot(CrannyTheme())
}
