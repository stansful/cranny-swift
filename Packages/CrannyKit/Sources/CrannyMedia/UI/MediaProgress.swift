// CrannyMedia/UI/MediaProgress.swift — the scrubber and its time labels (DESIGN.md §7.1): drag or scroll
// horizontally to seek (`.levelChange` haptic at every 10 %), ← / → ±10 s while focused (⌘← / ⌘→ pass through to
// the widget: previous / next), VoiceOver adjustable. A scroll previews for as long as the fingers move and seeks
// once, when they lift; a touch the system cancels seeks nowhere (`ScrollSeek`). The bar and its labels run left to
// right in every language (elapsed left, "−remaining" right): time-based media keeps its direction (Apple HIG).
// Energy (open issue 2, ARCHITECTURE.md §10.1): the position is interpolated from the provider's anchor
// (`NowPlaying.position(at:)`) once per second of playback by `PlaybackTicker` (one sleep per tick, aligned to the
// track's seconds), only while playing and on screen — never a display-rate TimelineView, never polling MediaRemote.
import CrannyCore
import SwiftUI

struct MediaProgress: View {
    enum Style { case stacked, inline, hairline }

    @Environment(\.cranny) private var theme
    @Environment(\.notchKeyboardNavigation) private var keyboardNavigation
    @FocusState private var focused: Bool
    @State private var preview: Double?          // fraction while dragging or scrolling
    @State private var scrollSeek = ScrollSeek()
    @State private var lastDecile: Int?
    @State private var width: CGFloat = 1
    let service: MediaService
    var style: Style = .stacked
    var haptics: Haptics?

    var body: some View {
        if let np = service.nowPlaying {
            if let duration = np.duration {
                PlaybackTicker(nowPlaying: np) { date in
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

    private func content(position: TimeInterval, duration: TimeInterval) -> some View {
        timeline(position: position, duration: duration).crannyLeftToRight()
    }

    @ViewBuilder private func timeline(position: TimeInterval, duration: TimeInterval) -> some View {
        let time = PlaybackTime(position: position, duration: duration)
        switch style {
        case .hairline:
            LevelBar(value: position / duration, tint: theme.accentColor, thickness: 2)
                .accessibilityHidden(true)
        case .inline:
            HStack(spacing: Space.m) {
                elapsedLabel(time)
                scrubber(position: position, duration: duration, time: time)
                remainingLabel(time)
            }
        case .stacked:
            VStack(spacing: 0) {
                scrubber(position: position, duration: duration, time: time)
                HStack {
                    elapsedLabel(time)
                    Spacer(minLength: Space.m)
                    remainingLabel(time)
                }
                .padding(.top, -Space.m)                 // under the 4-pt bar of the 24-pt hit target
            }
        }
    }

    private func elapsedLabel(_ time: PlaybackTime) -> some View {
        Text(verbatim: MediaStrings.clock(TimeInterval(time.elapsed)))
            .crannyFont(.caption).foregroundStyle(theme.palette.tertiaryLabel)
            .fixedSize()
            .accessibilityHidden(true)
    }

    private func remainingLabel(_ time: PlaybackTime) -> some View {
        Text(verbatim: MediaStrings.remaining(TimeInterval(time.remaining)))
            .crannyFont(.caption).foregroundStyle(theme.palette.tertiaryLabel)
            .fixedSize()
            .accessibilityHidden(true)
    }

    private func scrubber(position: TimeInterval, duration: TimeInterval, time: PlaybackTime) -> some View {
        Scrubber(value: position / duration, step: min(10 / duration, 1), label: MediaStrings.playbackPosition,
                 valueDescription: MediaStrings.timeLeft(TimeInterval(time.remaining))) { fraction in
            seek(to: fraction * duration)
        }
        .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { width = max($0, 1) }
        .simultaneousGesture(DragGesture(minimumDistance: 0)
            .onChanged { follow(fraction: $0.location.x / width) }
            .onEnded { _ in endFollowing() })
        .crannyContinuousScrollZone(ScrollZoneID("media.seek"), axis: .horizontal, onUpdate: scroll, onEnd: scrollEnded)
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .crannyFocusRing(focused && keyboardNavigation, radius: Radius.chip)
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

    /// Two-finger horizontal scroll over the scrubber, a continuous zone: `.tracking` for the whole touch (never a
    /// commit that would stop the preview part-way). The zone keeps the closures of its last layout, so the track's
    /// position and duration are read from the service when the scroll happens, not captured.
    private func scroll(_ update: SwipeUpdate) {
        guard case .tracking(_, let translation) = update,
              let np = service.nowPlaying, let duration = np.duration, duration > 0 else { return }
        let current = np.position(at: Date()) / duration
        follow(fraction: scrollSeek.track(translation: translation, width: width, current: current))
    }

    private func scrollEnded(_ end: NotchZones.ScrollEnd) {
        if let target = scrollSeek.end(end, preview: preview, duration: service.nowPlaying?.duration) {
            seek(to: target)
        }
        endFollowing()
    }
}

/// Scroll-to-seek over the scrubber (pure, unit-tested): the bar's width spans the whole track, the preview follows the
/// fingers from where the track was when the touch began, and only a release seeks.
struct ScrollSeek: Equatable {
    /// Fraction of the track where the touch began; nil between touches.
    private(set) var start: Double?

    /// The fraction to preview for `translation` pt of finger travel over a bar `width` pt wide. `current` (the track's
    /// fraction now) is used only by the first update of a touch.
    mutating func track(translation: CGFloat, width: CGFloat, current: Double) -> Double {
        let start = self.start ?? min(max(current, 0), 1)
        self.start = start
        return min(max(start + Double(translation / max(width, 1)), 0), 1)
    }

    /// The touch ended: seconds to seek to, or nil — the system cancelled the touch, nothing was previewed, or the
    /// track has no duration.
    mutating func end(_ end: NotchZones.ScrollEnd, preview: Double?, duration: TimeInterval?) -> TimeInterval? {
        start = nil
        guard end == .released, let preview, let duration, duration.isFinite, duration > 0 else { return nil }
        return min(max(preview, 0), 1) * duration
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
