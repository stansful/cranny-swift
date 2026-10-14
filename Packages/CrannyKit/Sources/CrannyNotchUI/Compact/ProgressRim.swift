// CrannyNotchUI/Compact/ProgressRim.swift — the lower rim of the compact shape (DESIGN.md §5.1, §5.5):
// playback progress as a 1.5-pt accent line (Appearance ▸ Progress rim, Now Playing only) and the one-shot
// green sweep when a charger connects (CrannyEffects' `ChargeSweep` along the same lower outline). Both are drawn
// inside the shape (the surface clips its content to it), so no pixel lands outside the notch.
import CrannyCore
import CrannyEffects
import SwiftUI

/// The lower outline of `geometry`: the shape's stroke below the band's middle, revealed left to right up
/// to `progress` (0…1), in every language: playback progress keeps its direction (CrannyCore's RightToLeft.swift).
/// Content of `NotchSurface`, so it sits in the canvas at the shape's place.
struct LowerRim: View {
    let geometry: NotchGeometry
    let progress: Double
    let color: Color

    var body: some View {
        let shape = NotchShape(geometry)
        shape.stroke(color, lineWidth: StrokeWidth.rim * 2)           // half of it is outside: clipped away
            .clipShape(shape)
            .mask(alignment: .top) { LowerRim.mask(geometry: geometry, progress: progress) }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .crannyLeftToRight()
    }

    /// Below the middle of the body, from the left edge to `progress` of the width (`LowerRim` lays it out left to right).
    static func mask(geometry g: NotchGeometry, progress: Double) -> some View {
        let p = CGFloat(min(max(progress, 0), 1))
        return HStack(spacing: 0) {
            Color.white.frame(width: g.bodyWidth * p)
            Spacer(minLength: 0)
        }
        .frame(width: g.bodyWidth, height: g.height / 2)
        .padding(.top, g.topInset + g.height / 2)
    }

    /// The same lower outline as a path in `rect` (the canvas the shape is centred in, as `NotchShape` draws it):
    /// from the leading side at the body's middle, down, along the bottom and up to the trailing side's middle.
    /// It runs half a rim inside the outline, so a 1.5-pt stroke on it lies inside the shape, and it is left to
    /// right and x-monotonic, as `ChargeSweep` needs. Pure (unit-tested); empty for a shape too small to have one.
    nonisolated static func outline(_ g: NotchGeometry, in rect: CGRect) -> Path {
        let inset = StrokeWidth.rim / 2
        let w = max(g.bodyWidth, 0), h = max(g.height, 0)
        guard w > 4 * inset, h > 4 * inset else { return Path() }
        let top = rect.minY + max(g.topInset, 0)
        let body = CGRect(x: rect.midX - w / 2, y: top, width: w, height: h).insetBy(dx: inset, dy: inset)
        let middle = top + h / 2
        // NotchShape's bottom radius, inset like the line (a quarter circle stands in for the continuous corner).
        let r = min(max(min(max(g.bottomRadius, 0), h / 2, w / 2) - inset, 0), body.maxY - middle, body.width / 2)
        let k: CGFloat = 0.5523                                  // cubic ≈ quarter circle
        var path = Path()
        path.move(to: CGPoint(x: body.minX, y: middle))
        path.addLine(to: CGPoint(x: body.minX, y: body.maxY - r))
        path.addCurve(to: CGPoint(x: body.minX + r, y: body.maxY),
                      control1: CGPoint(x: body.minX, y: body.maxY - r + k * r),
                      control2: CGPoint(x: body.minX + r - k * r, y: body.maxY))
        path.addLine(to: CGPoint(x: body.maxX - r, y: body.maxY))
        path.addCurve(to: CGPoint(x: body.maxX, y: body.maxY - r),
                      control1: CGPoint(x: body.maxX - r + k * r, y: body.maxY),
                      control2: CGPoint(x: body.maxX, y: body.maxY - r + k * r))
        path.addLine(to: CGPoint(x: body.maxX, y: middle))
        return path
    }
}

extension StrokeWidth {
    /// The progress rim and the charge sweep (DESIGN.md §5.1).
    nonisolated static let rim: CGFloat = 1.5
}

/// Playback progress of Now Playing along the rim, redrawn by an `EffectClock` only while the track plays and the
/// panel is on screen (not covered, not locked); otherwise it draws a still line and costs nothing. The clock ticks
/// once a second, unless the line takes two seconds or more to move one device pixel (a long mix, a podcast, an
/// audiobook): then once per whole number of seconds a pixel takes, so a tick never moves the line more than a pixel.
struct PlaybackRim: View {
    @Environment(\.cranny) private var theme
    @Environment(\.displayScale) private var displayScale
    let geometry: NotchGeometry
    let source: any NowPlayingSource
    /// `EffectBudget.onScreen` of the canvas.
    var isOnScreen = true

    var body: some View {
        if let playing = source.nowPlaying, let duration = playing.duration, duration > 0 {
            let interval = PlaybackRim.interval(duration: duration, rate: playing.rate,
                                                pixels: geometry.bodyWidth * displayScale)
            EffectClock(minimumInterval: playing.isPlaying && isOnScreen ? interval : nil) { date in
                LowerRim(geometry: geometry, progress: playing.position(at: date) / duration, color: theme.accentColor)
            }
        }
    }

    /// Seconds between redraws for a track of `duration` played at `rate` along a rim `pixels` device pixels wide:
    /// the whole seconds the line takes to move one pixel, at least 1 and at most `maximumInterval`. Whole seconds,
    /// so a small change of the rim's width rarely changes the schedule (a new one restarts the clock). Pure.
    nonisolated static func interval(duration: TimeInterval, rate: Double, pixels: CGFloat) -> Double {
        let speed = rate > 0 ? rate : 1                           // as `NowPlaying.position(at:)` advances
        let perPixel = duration / (max(Double(pixels), 1) * speed)
        guard perPixel.isFinite else { return 1 }
        return min(max(perPixel.rounded(.down), 1), maximumInterval)
    }

    /// The slowest redraw (a recording of many hours, whose line moves less than a pixel in this time). A seek,
    /// a pause or a new track redraws at once whatever the interval: the snapshot changes. That redraw still uses
    /// the last tick's date, so a seek while playing lands at most a pixel short until the next tick.
    nonisolated static let maximumInterval: Double = 30
}

/// The charger-connected sweep: CrannyEffects' `ChargeSweep`, a green head with a fading tail travelling leading →
/// trailing along `LowerRim.outline` in 0.8 s; Reduce Motion lights the whole rim at once and fades it (DESIGN.md
/// §5.5 "Instant rim"). Animatable, so the outline follows the shape while it morphs (an activity arriving with
/// its sweep).
struct ChargeSweepRim: View, Animatable {
    @Environment(\.cranny) private var theme
    var geometry: NotchGeometry
    /// The canvas's budget for moments: frame rate (AC / battery) and path (Reduce Motion, Low Power).
    let budget: EffectBudget

    nonisolated var animatableData: NotchGeometry {
        get { geometry }
        set { geometry = newValue }
    }

    var body: some View {
        let geometry = geometry
        GeometryReader { proxy in
            ChargeSweep(outline: LowerRim.outline(geometry, in: CGRect(origin: .zero, size: proxy.size)),
                        level: theme.effectiveAmbience, budget: budget)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

#Preview("Rim · progress 40 %") {
    let layout = NotchLayout(metrics: .reference)
    let g = layout.compact(.short)
    ZStack(alignment: .top) {
        NotchShape(g).fill(.black)
        LowerRim(geometry: g, progress: 0.4, color: .blue)
    }
    .frame(width: 360, height: 60, alignment: .top)
    .background(Color(white: 0.3))
    .crannyThemeRoot(CrannyTheme())
}
