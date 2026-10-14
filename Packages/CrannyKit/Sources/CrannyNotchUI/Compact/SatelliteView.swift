// CrannyNotchUI/Compact/SatelliteView.swift — the second concurrent activity (DESIGN.md §9.4): a Ø 24u black
// bubble 6u beyond the compact shape's trailing edge, vertically centred in the band, showing the activity's
// `minimal()` glyph. It buds off the shape with the `satellite` spring; in Standard and Lively CrannyEffects'
// `LiquidNeck` joins the two for the first 0.38 s (§4.3, §5.5). Click swaps it with the primary (a ≥ 32 × 24
// target, `SatelliteMetrics`); VoiceOver can dismiss it.
import CrannyCore
import CrannyEffects
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
    /// The canvas's budget for moments: which path draws the neck (shader, Canvas fallback).
    let budget: EffectBudget
    @State private var budded = false

    var body: some View {
        let d = NotchLayout.satelliteDiameter * layout.u
        let frame = SatellitePlacement.frame(layout: layout, compact: compact)
        let hit = SatelliteMetrics.hitSize(layout: layout)
        let travel = SatellitePlacement.budTravel(layout: layout, compact: compact)
        let budded = budded || rendersFinalState
        let showsNeck = !theme.reduceMotion && (theme.motion == .standard || theme.motion == .lively)
        ZStack {
            if showsNeck {
                SatelliteNeck(progress: budded ? 1 : 0, bubble: d, travel: travel, bandHeight: layout.rowHeight,
                              cornerRadius: compact.bottomRadius, budget: budget)
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
                // A band control: the click target is padded beyond the bubble to ≥ 32 × 24 (DESIGN.md §2.3).
                .frame(width: hit.width, height: hit.height)
                .contentShape(Rectangle())
                .onTapGesture { actions.satelliteTapped() }
                .offset(x: budded || !showsNeck ? 0 : -travel)
                .opacity(budded || showsNeck ? 1 : 0)
                .activityAccessibility(activity, id: id, open: actions.satelliteTapped, dismiss: { actions.dismissActivity(id) },
                                       openTitle: Text("Show", bundle: .module, comment: "Satellite: VoiceOver action that swaps it with the activity in the notch"))
        }
        .frame(width: hit.width, height: hit.height)
        .offset(x: frame.midX, y: frame.midY - hit.height / 2)
        .onAppear {
            guard !self.budded else { return }
            if let animation = theme.animation(.satellite) { withAnimation(animation) { self.budded = true } } else { self.budded = true }
        }
    }
}

/// The satellite's click target, for the shell's interactive rect (the panel passes clicks through everywhere
/// else). The Ø 24u bubble is a band control, so its target is padded to at least 32 × 24 (DESIGN.md §2.3,
/// ARCHITECTURE.md §9.5) around the same centre.
public enum SatelliteMetrics {
    /// Width and height of the click target on this display: ≥ 32 × 24 and never smaller than the bubble.
    public static func hitSize(layout: NotchLayout) -> CGSize {
        let d = NotchLayout.satelliteDiameter * layout.u
        return CGSize(width: max(d, HitTarget.band.width), height: max(d, HitTarget.band.height))
    }

    /// The click target beside `compact` in `canvas` coordinates (the same frame the satellite is drawn around:
    /// `NotchLayout.satelliteFrame(beside:in:)`, padded to `hitSize`).
    public static func hitFrame(beside compact: NotchGeometry, layout: NotchLayout, in canvas: CGRect) -> CGRect {
        let bubble = layout.satelliteFrame(beside: compact, in: canvas)
        let size = hitSize(layout: layout)
        return CGRect(x: bubble.midX - size.width / 2, y: bubble.midY - size.height / 2, width: size.width, height: size.height)
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

/// The satellite split (DESIGN.md §5.5): CrannyEffects' `LiquidNeck` over the strip from the body's trailing end to
/// the bubble, both drawn black under the real ones, so the two join with a concave neck that thins and snaps.
/// Animatable: the `satellite` spring drives `progress` frame by frame (no clock), and once the bubble has landed
/// nothing is drawn.
struct SatelliteNeck: View, Animatable {
    var progress: Double
    let bubble: CGFloat
    let travel: CGFloat
    let bandHeight: CGFloat
    let cornerRadius: CGFloat
    let budget: EffectBudget

    nonisolated var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        if progress < 1 {
            LiquidNeck(progress: progress, budget: budget) { bodies }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    /// The body's trailing end (a band-tall stub at the leading edge of this view, under the real body) and the
    /// bubble on its way out.
    private var bodies: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: min(cornerRadius, bandHeight / 2), style: .continuous)
                .fill(.black)
                .frame(width: bubble, height: bandHeight)
            Circle()
                .fill(.black)
                .frame(width: bubble, height: bubble)
                .offset(x: travel * CGFloat(progress), y: (bandHeight - bubble) / 2)
        }
        .frame(width: travel + bubble, height: bandHeight, alignment: .topLeading)
    }
}

#Preview("Satellite beside compact") {
    let (model, registry) = previewScene(.compact, satellite: true)
    NotchCanvasView(model: model, registry: registry)
        .frame(width: 520, height: 80)
        .background(Color(white: 0.25))
}
