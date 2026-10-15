// CrannyQuickApps/UI/ShortcutTileFace.swift — a shortcut tile's squircle and its run state (DESIGN.md §7.3):
// running = a 2.5-pt progress ring in place of the glyph · success = a check that bounces once · failure = a
// `danger` badge with "!" on the corner (the tooltip says why). Glyph swaps use `contentSwap`. The "+N" tile uses
// the same parts for the shortcuts it holds (`RunStateGlyph`, `shortcutFailureBadge`). Only the running ring reads the
// effect budget, so an idle tile never follows lock, Low Power, thermal or power-source changes.
import CrannyCore
import SwiftUI

struct ShortcutTileFace: View {
    let entry: ShortcutEntry
    let state: ShortcutRunState
    let metrics: TileMetrics
    let redacted: Bool
    /// Paces the running ring (`RunningRing`).
    let environment: any SystemEnvironment

    var body: some View {
        ShortcutGlyph(entry: entry, size: metrics.icon, redacted: redacted) {
            RunStateGlyph(state: state, metrics: metrics, environment: environment) {
                ShortcutMark(entry: entry, size: metrics.icon, redacted: redacted)
            }
        }
        .shortcutFailureBadge(state, metrics: metrics)
    }
}

/// The middle of a squircle for a run state: the progress ring while running, the check after a success, else
/// `mark` (the shortcut's glyph, or "+N" on the overflow tile). Swaps use `contentSwap`.
struct RunStateGlyph<Mark: View>: View {
    @Environment(\.cranny) private var theme
    let state: ShortcutRunState
    let metrics: TileMetrics
    /// Paces the running ring (`RunningRing`).
    let environment: any SystemEnvironment
    @ViewBuilder let mark: () -> Mark

    var body: some View {
        ZStack {
            switch state {
            case .running(let since):
                RunningRing(since: since, size: metrics.ring, environment: environment)
                    .transition(.opacity)
            case .succeeded:
                SuccessCheck(size: metrics.glyph)
                    .transition(theme.reduceMotion ? .opacity : .scale(scale: 0.6).combined(with: .opacity))
            case .idle, .failed:
                mark()
                    .transition(.opacity)
            }
        }
        .animation(theme.animation(.contentSwap), value: RunStateKey(state))
    }
}

extension View {
    /// The failure badge, centred just outside the top-trailing corner of a squircle drawn in an icon canvas of
    /// `metrics.icon` (DESIGN.md §7.3: a `danger` badge; the tooltip says why).
    func shortcutFailureBadge(_ state: ShortcutRunState, metrics: TileMetrics) -> some View {
        modifier(FailureBadgeOverlay(state: state, metrics: metrics))
    }
}

private struct FailureBadgeOverlay: ViewModifier {
    @Environment(\.cranny) private var theme
    let state: ShortcutRunState
    let metrics: TileMetrics

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .topTrailing) {
                if case .failed = state {
                    FailureBadge(size: metrics.badge)
                        .offset(x: metrics.badge * 0.35 - metrics.inset, y: metrics.inset - metrics.badge * 0.35)
                        .transition(theme.reduceMotion ? .opacity : .scale(scale: 0.5).combined(with: .opacity))
                }
            }
            .animation(theme.animation(.contentSwap), value: RunStateKey(state))
    }
}

/// Animation key without the start date (a new run of a running tile does not re-animate).
private enum RunStateKey: Equatable {
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

/// An indeterminate run shown as a ring that fills quickly, then ever more slowly (we never know how long a
/// shortcut takes). Ticks through `EffectClock` only while the effect budget allows (ARCHITECTURE.md §9.2), at
/// most 8 times a second; otherwise it holds its last frame (also while the panel is occluded: `notchIsOnScreen`).
/// Under Reduce Motion it rests at a quarter. The budget is read here, in the only view that needs it, so idle tiles
/// do not depend on it.
struct RunningRing: View {
    @Environment(\.cranny) private var theme
    @Environment(\.notchIsOnScreen) private var isOnScreen
    let since: Date
    let size: CGFloat
    let environment: any SystemEnvironment

    static func progress(elapsed: TimeInterval) -> Double {
        0.12 + 0.78 * (1 - exp(-max(elapsed, 0) / 4))
    }

    /// The ring's frame interval under `budget`: paused (nil) when the budget pauses effects (closed, off screen,
    /// full screen in front, Low Power or thermal state ≥ serious, Reduce Motion), else never faster than 8 fps.
    static func frameInterval(_ budget: EffectBudget) -> Double? {
        budget.minimumInterval.map { max($0, 1.0 / 8) }
    }

    var body: some View {
        let frameInterval = Self.frameInterval(environment.effectBudget(isOpen: true, isOnScreen: isOnScreen,
                                                                         reduceMotion: theme.reduceMotion))
        EffectClock(minimumInterval: frameInterval) { date in
            ProgressRing(progress: theme.reduceMotion ? 0.25 : Self.progress(elapsed: date.timeIntervalSince(since)),
                         color: .white, lineWidth: StrokeWidth.ringCompact)
        }
        .frame(width: size, height: size)
    }
}

/// The success check: bounces once when it appears (never under Reduce Motion or Motion ▸ Instant).
struct SuccessCheck: View {
    @Environment(\.cranny) private var theme
    let size: CGFloat
    @State private var bounce = false

    var body: some View {
        Image(systemName: "checkmark.circle.fill")
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(Color.white)
            .crannySymbolBounce(value: bounce)
            .onAppear { if theme.animatesSymbols { bounce.toggle() } }
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
    let environment = PreviewSystemEnvironment()
    HStack(spacing: Space.xl) {
        ShortcutTileFace(entry: entry, state: .idle, metrics: metrics, redacted: false, environment: environment)
        ShortcutTileFace(entry: entry, state: .running(since: .now), metrics: metrics, redacted: false, environment: environment)
        ShortcutTileFace(entry: entry, state: .succeeded, metrics: metrics, redacted: false, environment: environment)
        ShortcutTileFace(entry: entry, state: .failed(.shortcutFailed), metrics: metrics, redacted: false, environment: environment)
    }
    .padding(Space.xl)
    .background(.black)
    .crannyThemeRoot(CrannyTheme())
}
