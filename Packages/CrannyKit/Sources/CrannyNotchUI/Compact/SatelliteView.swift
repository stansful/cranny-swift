// CrannyNotchUI/Compact/SatelliteView.swift — the second concurrent activity (DESIGN.md §9.4): a Ø 24u black
// bubble 6u beyond the compact shape's trailing edge, vertically centred in the band, showing the activity's
// `minimal()` glyph. It buds off the shape with the `satellite` spring; in Standard and Lively a liquid neck
// joins the two for the first 0.38 s (§4.3, §5.5). Click swaps it with the primary; VoiceOver can dismiss it.
import CrannyCore
import Foundation
import SwiftUI

struct SatelliteView: View {
    @Environment(\.cranny) private var theme
    @Environment(\.notchRendersFinalState) private var rendersFinalState
    let id: ActivityID
    let activity: any LiveActivity
    let layout: NotchLayout
    /// The compact shape the bubble buds from (its current width).
    let compact: NotchGeometry
    let actions: NotchUIActions
    @State private var budded = false

    var body: some View {
        let d = NotchLayout.satelliteDiameter * layout.u
        let frame = SatellitePlacement.frame(layout: layout, compact: compact)
        let travel = SatellitePlacement.budTravel(layout: layout, compact: compact)
        let budded = budded || rendersFinalState
        let showsNeck = !theme.reduceMotion && (theme.motion == .standard || theme.motion == .lively)
        ZStack {
            if showsNeck {
                LiquidNeckFallback(progress: budded ? 1 : 0, reach: 7, bubble: d, travel: travel, bandHeight: layout.rowHeight,
                                   cornerRadius: compact.bottomRadius)
                    .frame(width: travel + d, height: layout.rowHeight)
                    .offset(x: -travel / 2)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            Circle().fill(theme.palette.surface)
                .frame(width: d, height: d)
                .overlay {
                    activity.view(for: .minimal)
                        .foregroundStyle(theme.palette.label)
                        .frame(width: d * 0.75, height: d * 0.75)
                        .opacity(budded ? 1 : 0)
                }
                .contentShape(Circle())
                .onTapGesture { actions.satelliteTapped() }
                .offset(x: budded || !showsNeck ? 0 : -travel)
                .opacity(budded || showsNeck ? 1 : 0)
                .activityAccessibility(activity, id: id, open: actions.satelliteTapped, dismiss: { actions.dismissActivity(id) },
                                       openTitle: Text("Show", bundle: .module, comment: "Satellite: VoiceOver action that swaps it with the activity in the notch"))
        }
        .frame(width: d, height: d)
        .offset(x: frame.midX, y: frame.minY)
        .onAppear {
            guard !self.budded else { return }
            if let animation = theme.animation(.satellite) { withAnimation(animation) { self.budded = true } } else { self.budded = true }
        }
    }
}

/// Where the bubble sits, relative to the canvas's top centre (pure, unit-tested against DESIGN.md §3.3).
nonisolated enum SatellitePlacement {
    /// `minX`/`midX` are measured from the canvas's horizontal centre; `minY`/`midY` from its top.
    static func frame(layout: NotchLayout, compact: NotchGeometry) -> CGRect {
        let canvas = CGRect(x: -1000, y: 0, width: 2000, height: 1000)      // centred at x = 0
        return layout.satelliteFrame(beside: compact, in: canvas)
    }

    /// How far the bubble's centre travels while it buds: from just inside the body's trailing end to its
    /// place (6u gap + one diameter).
    static func budTravel(layout: NotchLayout, compact: NotchGeometry) -> CGFloat {
        let d = NotchLayout.satelliteDiameter * layout.u
        return frame(layout: layout, compact: compact).midX - (compact.bodyWidth / 2 - d / 2)
    }
}

/// Fallback of the `liquidNeck` shader (DESIGN.md §5.6): the body's trailing end and the bubble, blurred
/// and alpha-thresholded, so two shapes closer than ≈ 2 · reach merge with a concave neck that thins and snaps.
/// Animatable: SwiftUI redraws it only while the `satellite` spring runs (no clock).
private struct LiquidNeckFallback: View, Animatable {
    var progress: Double
    let reach: CGFloat
    let bubble: CGFloat
    let travel: CGFloat
    let bandHeight: CGFloat
    let cornerRadius: CGFloat

    nonisolated var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        let r = reach * CGFloat(1 - smoothstep(0.7, 1, progress))
        Canvas(opaque: false) { context, size in
            guard r > 0.2 else { return }
            context.addFilter(.alphaThreshold(min: 0.5, color: .black))
            context.addFilter(.blur(radius: r))
            context.drawLayer { layer in
                // The body's trailing end: a band-tall stub at the leading edge of this view, under the real body.
                layer.fill(Path(roundedRect: CGRect(x: 0, y: 0, width: bubble, height: bandHeight),
                                cornerRadius: min(cornerRadius, bandHeight / 2), style: .continuous), with: .color(.black))
                let x = travel * CGFloat(progress)
                layer.fill(Path(ellipseIn: CGRect(x: x, y: (bandHeight - bubble) / 2, width: bubble, height: bubble)), with: .color(.black))
            }
        }
        .opacity(progress < 1 ? 1 : 0)
    }

    private func smoothstep(_ a: Double, _ b: Double, _ x: Double) -> Double {
        let t = min(max((x - a) / (b - a), 0), 1)
        return t * t * (3 - 2 * t)
    }
}

#Preview("Satellite beside compact") {
    let (model, registry) = previewScene(.compact, satellite: true)
    NotchCanvasView(model: model, registry: registry)
        .frame(width: 520, height: 80)
        .background(Color(white: 0.25))
}
