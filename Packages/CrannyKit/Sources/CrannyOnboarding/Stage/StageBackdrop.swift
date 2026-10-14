// CrannyOnboarding/Stage/StageBackdrop.swift — the stage's "desktop": a dark brand gradient with the brand
// aurora at Subtle rising from the bottom (DESIGN.md §12.1), and a quiet wireframe menu bar the notch sits in.
// The aurora follows the theme's light (off under Reduce Transparency or with Ambient light off, capped at Subtle)
// and gives way, with the ambient fades, to the open panel's own light, so one light runs at a time. It takes its
// time from `EffectClock` through `EffectBudget`: it pauses while the window is hidden and freezes a resting frame
// under Reduce Motion (DESIGN.md §4.7).
import CrannyCore
import CrannyEffects
import SwiftUI

struct StageBackdrop: View {
    @Environment(\.cranny) private var theme
    /// ImageRenderer snapshots cannot see CrannyEffects' Metal layer: they keep the light in SwiftUI.
    @Environment(\.isStaticSnapshot) private var isStaticSnapshot
    /// `.off` draws the desktop alone.
    let level: AmbienceLevel
    let budget: EffectBudget

    var body: some View {
        ZStack {
            LinearGradient(colors: [BrandColor.night.color, BrandColor.graphite.color], startPoint: .top, endPoint: .bottom)
            if level != .off {
                AuroraField(palette: .afterglow, level: level, energy: 0, budget: budget)
                    .ambientLightRendering(isStaticSnapshot ? .inline : .automatic)
                    .transition(.opacity)
            }
        }
        .animation(theme.animation(level == .off ? .ambientOut : .ambientIn), value: level)
        .accessibilityHidden(true)
    }

    /// The desktop's light: the brand aurora at Subtle at most, off when the theme's light is off and while the
    /// stage's open panel draws its own light layer.
    static func level(theme: CrannyTheme, panelDrawsLight: Bool) -> AmbienceLevel {
        panelDrawsLight ? .off : min(.subtle, theme.effectiveAmbience)
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
        StageBackdrop(level: .subtle, budget: EffectBudget(isOpen: true, onScreen: true, lowPower: false,
                                                           fullScreenFront: false, reduceMotion: true, onBattery: false))
        StageMenuBar(band: 32)
    }
    .frame(width: WelcomeMetrics.stageSize.width, height: WelcomeMetrics.stageSize.height)
    .crannyThemeRoot(CrannyTheme())
}
