// CrannyMedia/UI/MediaProgress.swift — the scrubber and its time labels (DESIGN.md §7.1): drag or scroll
// horizontally to seek (`.levelChange` haptic at every 10 %), ← / → ±10 s while focused (⌘← / ⌘→ pass through to
// the widget: previous / next), VoiceOver adjustable.
// Energy (open issue 2, ARCHITECTURE.md §10.1): the position is interpolated from the provider's anchor
// (`NowPlaying.position(at:)`) once per second by `EffectClock(minimumInterval: 1)`, only while playing and on
// screen — never a display-rate TimelineView, never polling MediaRemote.
import CrannyCore
import SwiftUI

struct MediaProgress: View {
    enum Style { case stacked, inline, hairline }

    @Environment(\.cranny) private var theme
    @Environment(\.notchContext) private var notch
    @FocusState private var focused: Bool
    @State private var preview: Double?          // fraction while dragging or scrolling
    @State private var scrollStart: Double?
    @State private var lastDecile: Int?
    @State private var width: CGFloat = 1
    let service: MediaService
    var style: Style = .stacked
    var haptics: Haptics?

    var body: some View {
        if let np = service.nowPlaying {
            if let duration = np.duration {
                EffectClock(minimumInterval: np.isPlaying ? 1 : nil) { date in
                    let position = preview.map { $0 * duration } ?? np.position(at: date)
                    content(position: position, duration: duration)
                        // One step per second, no glide: an animated bar would redraw at display rate.
                        .transaction { $0.disablesAnimations = true }
                }
            } else {
                Text(verbatim: MediaStrings.live).crannyFont(.micro)
                    .foregroundStyle(theme.palette.secondaryLabel)
                    .frame(maxWidth: .infinity, alignment: style == .inline ? .center : .leading)
                    .accessibilityLabel(Text(verbatim: MediaStrings.live))
            }
        }
    }

    @ViewBuilder private func content(position: TimeInterval, duration: TimeInterval) -> some View {
        switch style {
        case .hairline:
            LevelBar(value: position / duration, tint: theme.accentColor, thickness: 2)
                .accessibilityHidden(true)
        case .inline:
            HStack(spacing: Space.m) {
                elapsedLabel(position)
                scrubber(position: position, duration: duration)
                remainingLabel(position, duration)
            }
        case .stacked:
            VStack(spacing: 0) {
                scrubber(position: position, duration: duration)
                HStack {
                    elapsedLabel(position)
                    Spacer(minLength: Space.m)
                    remainingLabel(position, duration)
                }
                .padding(.top, -Space.m)                 // under the 4-pt bar of the 24-pt hit target
            }
        }
    }

    private func elapsedLabel(_ position: TimeInterval) -> some View {
        Text(verbatim: MediaStrings.clock(position))
            .crannyFont(.caption).foregroundStyle(theme.palette.tertiaryLabel)
            .fixedSize()
            .accessibilityHidden(true)
    }

    private func remainingLabel(_ position: TimeInterval, _ duration: TimeInterval) -> some View {
        Text(verbatim: "\u{2212}" + MediaStrings.clock(duration - position))
            .crannyFont(.caption).foregroundStyle(theme.palette.tertiaryLabel)
            .fixedSize()
            .accessibilityHidden(true)
    }

    private func scrubber(position: TimeInterval, duration: TimeInterval) -> some View {
        Scrubber(value: position / duration, step: min(10 / duration, 1), label: MediaStrings.playbackPosition,
                 valueDescription: MediaStrings.timeLeft(duration - position)) { fraction in
            seek(to: fraction * duration)
        }
        .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { width = max($0, 1) }
        .simultaneousGesture(DragGesture(minimumDistance: 0)
            .onChanged { follow(fraction: $0.location.x / width) }
            .onEnded { _ in endFollowing() })
        .crannyScrollZone(ScrollZoneID("media.seek"), axis: .horizontal) { update in
            scroll(update, position: position, duration: duration)
        }
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .crannyFocusRing(focused && notch.keyboardNavigation, radius: Radius.chip)
        // `onKeyPress(.leftArrow)` would also take ⌘←; with ⌘ / ⌥ / ⌃ held the press goes on to the widget
        // (⌘← / ⌘→ previous / next). Arrow keys carry the function / numeric-pad flags, so those are allowed.
        .onKeyPress(keys: [.leftArrow, .rightArrow]) { press in
            guard press.modifiers.isDisjoint(with: [.command, .option, .control]) else { return .ignored }
            seek(to: position + (press.key == .leftArrow ? -10 : 10))
            return .handled
        }
    }

    // MARK: Seeking

    private func seek(to seconds: TimeInterval) {
        let duration = service.nowPlaying?.duration ?? .infinity
        Task { await service.send(.seek(to: min(max(seconds, 0), duration))) }
    }

    /// Drag and scroll previews: the labels follow, with a `.levelChange` detent every 10 %.
    private func follow(fraction: Double) {
        let clamped = min(max(fraction, 0), 1)
        let decile = Int(clamped * 10)
        if let lastDecile, decile != lastDecile { haptics?.play(.levelChange) }
        lastDecile = decile
        preview = clamped
    }

    private func endFollowing() {
        preview = nil
        lastDecile = nil
    }

    /// Two-finger horizontal scroll over the scrubber: the bar's width spans the whole track.
    private func scroll(_ update: SwipeUpdate, position: TimeInterval, duration: TimeInterval) {
        let start = scrollStart ?? position / duration
        switch update {
        case .tracking(_, let translation):
            scrollStart = start
            follow(fraction: start + translation / width)
        case .committed, .cancelled:
            if let target = preview { seek(to: target * duration) }
            scrollStart = nil
            endFollowing()
        }
    }
}

#Preview("Progress · stacked, inline, hairline") {
    let service = SampleMedia.previewService()
    VStack(alignment: .leading, spacing: Space.xl) {
        MediaProgress(service: service).frame(width: 180)
        MediaProgress(service: service, style: .inline).frame(width: 224)
        MediaProgress(service: service, style: .hairline).frame(width: 160)
    }
    .padding(Space.xxl)
    .background(.black)
    .crannyThemeRoot(CrannyTheme())
}
