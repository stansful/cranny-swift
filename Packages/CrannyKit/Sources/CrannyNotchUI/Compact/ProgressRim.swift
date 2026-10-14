// CrannyNotchUI/Compact/ProgressRim.swift — the lower rim of the compact shape (DESIGN.md §5.1, §5.5):
// playback progress as a 1.5-pt accent line (Appearance ▸ Progress rim, Now Playing only) and the one-shot
// green sweep when a charger connects. Both are drawn inside the shape (the stroke is clipped to it), so no
// pixel lands outside the notch.
import CrannyCore
import SwiftUI

/// The lower outline of `geometry`: the shape's stroke below the band's middle, revealed left to right up
/// to `progress` (0…1). Content of `NotchSurface`, so it sits in the canvas at the shape's place.
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
    }

    /// Below the middle of the body, from the leading edge to `progress` of the width.
    static func mask(geometry g: NotchGeometry, progress: Double) -> some View {
        let p = CGFloat(min(max(progress, 0), 1))
        return HStack(spacing: 0) {
            Color.white.frame(width: g.bodyWidth * p)
            Spacer(minLength: 0)
        }
        .frame(width: g.bodyWidth, height: g.height / 2)
        .padding(.top, g.topInset + g.height / 2)
    }
}

extension StrokeWidth {
    /// The progress rim and the charge sweep (DESIGN.md §5.1).
    static let rim: CGFloat = 1.5
}

/// Playback progress of Now Playing along the rim. One redraw per second (`EffectClock`), only while the
/// track plays and the panel is on screen (not covered, not locked); otherwise it draws a still line and costs
/// nothing.
struct PlaybackRim: View {
    @Environment(\.cranny) private var theme
    let geometry: NotchGeometry
    let source: any NowPlayingSource
    /// `EffectBudget.onScreen` of the canvas.
    var isOnScreen = true

    var body: some View {
        if let playing = source.nowPlaying, let duration = playing.duration, duration > 0 {
            EffectClock(minimumInterval: playing.isPlaying && isOnScreen ? 1 : nil) { date in
                LowerRim(geometry: geometry, progress: playing.position(at: date) / duration, color: theme.accentColor)
            }
        }
    }
}

/// The charger-connected sweep: a green head with a fading tail travelling leading → trailing in 0.8 s.
/// Reduce Motion: the whole rim lights at once and fades (DESIGN.md §5.5 "Instant rim").
struct ChargeSweepRim: View {
    @Environment(\.cranny) private var theme
    let geometry: NotchGeometry
    let playback: DelightPlayback
    /// `DelightPlayback.frameInterval`: nil (paused) while not visible.
    let frameInterval: Double?

    var body: some View {
        let green = theme.palette.success
        if theme.reduceMotion {
            LowerRim(geometry: geometry, progress: 1, color: green)
                .modifier(RimFade(duration: playback.lifetime))
        } else {
            EffectClock(minimumInterval: frameInterval) { date in
                LowerRim(geometry: geometry, progress: 1, color: green)
                    .mask {
                        LinearGradient(stops: ChargeSweepProfile.stops(progress: playback.progress(at: date)),
                                       startPoint: .leading, endPoint: .trailing)
                            .frame(width: geometry.bodyWidth)
                    }
            }
        }
    }
}

private struct RimFade: ViewModifier {
    let duration: Double
    @State private var visible = true
    func body(content: Content) -> some View {
        content.opacity(visible ? 1 : 0)
            .onAppear { withAnimation(.easeIn(duration: duration)) { visible = false } }
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
