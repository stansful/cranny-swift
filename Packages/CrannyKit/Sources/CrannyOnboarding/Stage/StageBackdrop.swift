// CrannyOnboarding/Stage/StageBackdrop.swift — the stage's "desktop": a dark brand gradient with the brand
// aurora at Subtle rising from the bottom (DESIGN.md §12.1), and a quiet wireframe menu bar the notch sits in.
// The aurora takes its time from `EffectClock` through `EffectBudget`: it pauses while the window is hidden
// and freezes a resting frame under Reduce Motion (DESIGN.md §4.7).
import CrannyCore
import CrannyEffects
import SwiftUI

struct StageBackdrop: View {
    let budget: EffectBudget

    var body: some View {
        ZStack {
            LinearGradient(colors: [BrandColor.night.color, BrandColor.graphite.color], startPoint: .top, endPoint: .bottom)
            AuroraField(palette: .afterglow, level: .subtle, energy: 0, budget: budget)
        }
        .accessibilityHidden(true)
    }
}

/// The menu bar of the miniature screen: a translucent strip with placeholder items, so the notch reads as
/// "the top of your screen" without imitating any real menu. `band` is the notch (or menu bar) height.
struct StageMenuBar: View {
    @Environment(\.cranny) private var theme
    let band: CGFloat

    /// Leading placeholders start after the window's traffic lights and stay clear of a 185-pt camera housing.
    private static let leadingStart: CGFloat = 84
    private static let leading: [CGFloat] = [22, 34, 28]
    private static let trailing: [CGFloat] = [14, 14, 18, 52]

    var body: some View {
        let p = theme.palette
        HStack(spacing: Space.l) {
            ForEach(Array(Self.leading.enumerated()), id: \.offset) { _, width in placeholder(width) }
            Spacer(minLength: 0)
            ForEach(Array(Self.trailing.enumerated()), id: \.offset) { _, width in placeholder(width) }
        }
        .padding(.leading, Self.leadingStart)
        .padding(.trailing, Space.xl)
        .frame(height: band)
        .frame(maxWidth: .infinity)
        .background(p.well)
        .overlay(alignment: .bottom) { Rectangle().fill(p.hairline).frame(height: StrokeWidth.regular) }
        .accessibilityHidden(true)
    }

    private func placeholder(_ width: CGFloat) -> some View {
        Capsule(style: .continuous)
            .fill(theme.palette.quaternaryLabel.opacity(0.5))
            .frame(width: width, height: Space.s)
    }
}

#Preview("Stage backdrop") {
    ZStack(alignment: .top) {
        StageBackdrop(budget: EffectBudget(isOpen: true, onScreen: true, lowPower: false, fullScreenFront: false,
                                           reduceMotion: true, onBattery: false))
        StageMenuBar(band: 32)
    }
    .frame(width: WelcomeMetrics.stageSize.width, height: WelcomeMetrics.stageSize.height)
    .crannyThemeRoot(CrannyTheme())
}
