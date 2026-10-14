// CrannyQuickApps/UI/ShortcutTileFace.swift — a shortcut tile's squircle and its run state (DESIGN.md §7.3):
// running = a 2.5-pt progress ring in place of the glyph · success = a check that bounces once · failure = a
// `danger` badge with "!" on the corner (the tooltip says why). Glyph swaps use `contentSwap`.
import CrannyCore
import SwiftUI

struct ShortcutTileFace: View {
    @Environment(\.cranny) private var theme
    let entry: ShortcutEntry
    let state: ShortcutRunState
    let metrics: TileMetrics
    let redacted: Bool
    /// Low Power Mode: the ring holds still (it still says "running").
    let isLowPower: Bool

    var body: some View {
        ShortcutGlyph(entry: entry, size: metrics.icon, redacted: redacted) {
            switch state {
            case .running(let since):
                RunningRing(since: since, size: metrics.ring, isAnimated: !theme.reduceMotion && !isLowPower)
                    .transition(.opacity)
            case .succeeded:
                SuccessCheck(size: metrics.glyph)
                    .transition(theme.reduceMotion ? .opacity : .scale(scale: 0.6).combined(with: .opacity))
            case .idle, .failed:
                ShortcutMark(entry: entry, size: metrics.icon, redacted: redacted)
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .topTrailing) {
            if case .failed = state {
                // Centred just outside the squircle's top-trailing corner.
                FailureBadge(size: metrics.badge)
                    .offset(x: metrics.badge * 0.35 - metrics.inset, y: metrics.inset - metrics.badge * 0.35)
                    .transition(theme.reduceMotion ? .opacity : .scale(scale: 0.5).combined(with: .opacity))
            }
        }
        .animation(theme.animation(.contentSwap), value: StateKey(state))
    }

    /// Animation key without the start date (a new run of a running tile does not re-animate).
    private enum StateKey: Equatable {
        case idle, running, succeeded, failed
        init(_ state: ShortcutRunState) {
            switch state {
            case .idle: self = .idle
            case .running: self = .running
            case .succeeded: self = .succeeded
            case .failed: self = .failed
            }
        }
    }
}

/// An indeterminate run shown as a ring that fills quickly, then ever more slowly (we never know how long a
/// shortcut takes). Ticks at 8 fps through `EffectClock` only while visible; still under Reduce Motion.
struct RunningRing: View {
    let since: Date
    let size: CGFloat
    let isAnimated: Bool

    static func progress(elapsed: TimeInterval) -> Double {
        0.12 + 0.78 * (1 - exp(-max(elapsed, 0) / 4))
    }

    var body: some View {
        EffectClock(minimumInterval: isAnimated ? 1.0 / 8 : nil) { date in
            ProgressRing(progress: isAnimated ? Self.progress(elapsed: date.timeIntervalSince(since)) : 0.25,
                         color: .white, lineWidth: StrokeWidth.ringCompact)
        }
        .frame(width: size, height: size)
    }
}

/// The success check: bounces once when it appears (never under Reduce Motion).
struct SuccessCheck: View {
    @Environment(\.cranny) private var theme
    let size: CGFloat
    @State private var bounce = false

    var body: some View {
        Image(systemName: "checkmark.circle.fill")
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(Color.white)
            .symbolEffect(.bounce, value: bounce)
            .onAppear { if !theme.reduceMotion { bounce.toggle() } }
    }
}

/// `danger` circle with "!" (the glyph carries the meaning without colour), ringed in black to sit on any tint.
struct FailureBadge: View {
    @Environment(\.cranny) private var theme
    let size: CGFloat

    var body: some View {
        Image(systemName: "exclamationmark")
            .font(.system(size: (size * 0.6).rounded(), weight: .heavy))
            .foregroundStyle(theme.palette.label)
            .frame(width: size, height: size)
            .background(Circle().fill(theme.palette.danger))
            .overlay(Circle().strokeBorder(theme.palette.surface, lineWidth: StrokeWidth.emphasis))
            .accessibilityHidden(true)
    }
}

#Preview("Shortcut states") {
    let metrics = TileMetrics(tile: 56, showsLabels: false)
    let entry = ShortcutEntry(id: "A", name: "Morning routine", symbol: "sun.max.fill", tint: .orange)
    HStack(spacing: Space.xl) {
        ShortcutTileFace(entry: entry, state: .idle, metrics: metrics, redacted: false, isLowPower: false)
        ShortcutTileFace(entry: entry, state: .running(since: .now), metrics: metrics, redacted: false, isLowPower: false)
        ShortcutTileFace(entry: entry, state: .succeeded, metrics: metrics, redacted: false, isLowPower: false)
        ShortcutTileFace(entry: entry, state: .failed(.shortcutFailed), metrics: metrics, redacted: false, isLowPower: false)
    }
    .padding(Space.xl)
    .background(.black)
    .crannyThemeRoot(CrannyTheme())
}
