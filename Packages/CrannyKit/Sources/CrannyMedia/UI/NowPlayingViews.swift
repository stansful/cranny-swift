// CrannyMedia/UI/NowPlayingViews.swift — the four presentations of Now Playing (DESIGN.md §9.1–§9.3):
// compact leading (artwork 20u r 5u, or a note glyph), compact trailing (5-bar visualizer, 3-pt dots when
// paused), minimal (satellite artwork) and the 52-pt peek row (artwork 40 r 10 · title / artist · ⏮ ⏯ ⏭ · 2-pt
// progress). Activities never hard-code colours: tokens from the environment.
import CrannyCore
import SwiftUI

struct NowPlayingLeading: View {
    @Environment(\.cranny) private var theme
    let activity: NowPlayingActivity

    var body: some View {
        let service = activity.service
        let size = 20 * theme.notchUnit
        if service.settings[MediaSettings.artworkInCompact] {
            ArtworkView(image: service.artwork, identity: service.artworkKey,
                        size: size, radius: Radius.artCompact * theme.notchUnit,
                        glows: service.settings[CoreSettings.albumGlow], accent: service.palette?.accent)
                .notchMatched(MatchedID.mediaArtwork)
        } else {
            Image(systemName: "music.note")
                .font(.system(size: 13 * theme.notchUnit, weight: .semibold))
                .foregroundStyle(theme.palette.label)
                .frame(width: size, height: size)
                .accessibilityHidden(true)
        }
    }
}

struct NowPlayingTrailing: View {
    @Environment(\.cranny) private var theme
    let activity: NowPlayingActivity

    var body: some View {
        let np = activity.service.nowPlaying
        VisualizerBars(engine: activity.service.visualizer, isPlaying: np?.isPlaying ?? false,
                       trackKey: np?.trackKey, metrics: .compact(unit: theme.notchUnit))
    }
}

/// The satellite: ONE visual (DESIGN.md §9.4) — the artwork in a circle.
struct NowPlayingMinimal: View {
    @Environment(\.cranny) private var theme
    let activity: NowPlayingActivity

    var body: some View {
        let size = 18 * theme.notchUnit
        ArtworkView(image: activity.service.artwork, identity: activity.service.artworkKey,
                    size: size, radius: size / 2, accent: activity.service.palette?.accent)
    }
}

/// `[12] [artwork 40, r 10] [12] [title / artist + 2-pt progress] [8] [⏮ ⏯ ⏭, 28 pt] [12]` — the shell adds
/// the outer 12-pt margins and the 52-pt height.
struct NowPlayingPeekRow: View {
    @Environment(\.cranny) private var theme
    let activity: NowPlayingActivity

    var body: some View {
        let service = activity.service
        if let np = service.nowPlaying {
            HStack(spacing: Space.l) {
                ArtworkView(image: service.artwork, identity: service.artworkKey,
                            size: 40, radius: Radius.artPeek,
                            glows: service.settings[CoreSettings.albumGlow], accent: service.palette?.accent)
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: np.title).crannyFont(.headline).foregroundStyle(theme.palette.label)
                        .lineLimit(1).truncationMode(.tail)
                    if let subtitle = np.artist ?? np.album {
                        Text(verbatim: subtitle).crannyFont(.callout).foregroundStyle(theme.palette.secondaryLabel)
                            .lineLimit(1).truncationMode(.tail)
                    }
                    MediaProgress(service: service, style: .hairline)
                        .frame(height: 2)
                        .padding(.top, Space.xs)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: activity.accessibilityLabel))
                .accessibilityValue(Text(verbatim: activity.accessibilityValue ?? ""))
                Spacer(minLength: Space.m)
                if service.supportsCommands {
                    TransportControls(service: service, prominentPlayPause: false, spacing: 0)
                }
            }
        }
    }
}

// MARK: - Previews

#Preview("Now Playing · compact, satellite and peek") {
    let service = SampleMedia.previewService()
    let activity = NowPlayingActivity(service: service, settings: service.settings)
    let layout = NotchLayout(metrics: .reference)
    VStack(spacing: Space.xl) {
        CompactSlots(layout: layout, slot: activity.slot,
                     leading: { activity.compactLeading() }, center: { EmptyView() }, trailing: { activity.compactTrailing() })
            .frame(width: layout.compact(.short).bodyWidth)
            .background(Color.black)
        activity.minimal()
            .frame(width: 24, height: 24)
            .background(Circle().fill(Color.black))
        activity.peekRow()
            .padding(.horizontal, Space.l)
            .frame(width: layout.peek().bodyWidth, height: NotchLayout.peekRow)
            .background(Color.black)
    }
    .padding(Space.xxl)
    .background(Color(white: 0.15))
    .crannyThemeRoot(CrannyTheme())
}

#Preview("Now Playing · paused, no artwork in compact") {
    let service = SampleMedia.previewService(playing: false)
    let activity = NowPlayingActivity(service: service, settings: service.settings)
    VStack(spacing: Space.xl) {
        HStack(spacing: Space.xl) { activity.compactLeading(); activity.compactTrailing() }
        activity.peekRow().frame(width: 400, height: NotchLayout.peekRow)
    }
    .padding(Space.xxl)
    .background(.black)
    .crannyThemeRoot(CrannyTheme())
}
