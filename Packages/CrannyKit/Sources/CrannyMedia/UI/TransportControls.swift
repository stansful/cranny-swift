// CrannyMedia/UI/TransportControls.swift — ⏮ ⏯ ⏭ (+ shuffle and repeat at 6 cells), DESIGN.md §7.1/§9.3:
// 28-pt plain buttons around a 32-pt prominent play/pause (white, black glyph) in the widget; three 28-pt plain
// buttons in the peek row. The play glyph swaps with `.symbolEffect(.replace)`. Left to right in every language
// (⏮ before ⏭, as the glyphs point: Apple HIG, Right to left ▸ Controls; CrannyCore's RightToLeft.swift).
import CrannyCore
import SwiftUI

struct TransportControls: View {
    @Environment(\.cranny) private var theme
    let service: MediaService
    var prominentPlayPause = true
    var showsModes = false
    var spacing: CGFloat = Space.m

    var body: some View {
        let np = service.nowPlaying
        let playing = np?.isPlaying ?? false
        HStack(spacing: spacing) {
            if showsModes { ShuffleButton(service: service) }
            button(MediaStrings.previousTrack, symbol: "backward.fill", command: .previousTrack)
            Button { Task { await service.send(.togglePlayPause) } } label: {
                Image(systemName: playing ? "pause.fill" : "play.fill")
                    .contentTransition(theme.symbolReplace)
            }
            .buttonStyle(CrannyIconButtonStyle(prominentPlayPause ? .prominent : .plain,
                                               size: prominentPlayPause ? HitTarget.band.width : HitTarget.preferred))
            .help(playing ? MediaStrings.pause : MediaStrings.play)
            .accessibilityLabel(Text(verbatim: playing ? MediaStrings.pause : MediaStrings.play))
            button(MediaStrings.nextTrack, symbol: "forward.fill", command: .nextTrack)
            if showsModes { RepeatButton(service: service) }
        }
        .disabled(np == nil || !service.supportsCommands)
        .crannyLeftToRight()
    }

    private func button(_ title: String, symbol: String, command: MediaCommand) -> some View {
        Button { Task { await service.send(command) } } label: { Image(systemName: symbol) }
            .buttonStyle(CrannyIconButtonStyle(.plain))
            .help(title)
            .accessibilityLabel(Text(verbatim: title))
    }
}

/// Shuffle off ⇄ tracks. Accent while on; the state is also in VoiceOver's value (never colour alone).
private struct ShuffleButton: View {
    @Environment(\.cranny) private var theme
    let service: MediaService

    var body: some View {
        let on = (service.nowPlaying?.shuffle ?? .off) != .off
        Button { Task { await service.send(.setShuffle(on ? .off : .tracks)) } } label: {
            Image(systemName: "shuffle").foregroundStyle(on ? theme.accentColor : theme.palette.secondaryLabel)
        }
        .buttonStyle(CrannyIconButtonStyle(on ? .filled : .plain))
        .help(MediaStrings.shuffle)
        .accessibilityLabel(Text(verbatim: MediaStrings.shuffle))
        .accessibilityValue(Text(verbatim: on ? MediaStrings.shuffleOn : MediaStrings.off))
    }
}

/// Repeat off → all → one → off.
private struct RepeatButton: View {
    @Environment(\.cranny) private var theme
    let service: MediaService

    var body: some View {
        let mode = service.nowPlaying?.repeatMode ?? .off
        let next: RepeatMode = switch mode { case .off: .all; case .all: .one; case .one: .off }
        Button { Task { await service.send(.setRepeat(next)) } } label: {
            // `repeat` is the only repeat glyph in DESIGN.md §14.1: "repeat one" adds a small 1.
            Image(systemName: "repeat")
                .foregroundStyle(mode == .off ? theme.palette.secondaryLabel : theme.accentColor)
                .overlay(alignment: .topTrailing) {
                    if mode == .one {
                        Text(verbatim: "1").crannyFont(.micro)
                            .foregroundStyle(theme.accentColor)
                            .offset(x: Space.s, y: -Space.s)
                    }
                }
        }
        .buttonStyle(CrannyIconButtonStyle(mode == .off ? .plain : .filled))
        .help(MediaStrings.repeatMode)
        .accessibilityLabel(Text(verbatim: MediaStrings.repeatMode))
        .accessibilityValue(Text(verbatim: mode == .off ? MediaStrings.off : mode == .one ? MediaStrings.repeatOne : MediaStrings.repeatAll))
    }
}

#Preview("Transport · widget and peek") {
    let service = SampleMedia.previewService()
    VStack(spacing: Space.xl) {
        TransportControls(service: service, showsModes: true)
        TransportControls(service: service, prominentPlayPause: false, spacing: 0)
    }
    .padding(Space.xxl)
    .background(.black)
    .crannyThemeRoot(CrannyTheme())
}
