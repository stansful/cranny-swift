// CrannyNotchUI/Nook/NookLightLayer.swift — the light behind the open panel (DESIGN.md §5). It fills the frame
// the canvas gives it (`LightFrame`: the shape's body at its CURRENT, animating size), so it rides the bottom
// edge as the panel opens; fills with `ambientIn` and drains with `ambientOut`; cross-fades palettes with
// `colorShift`; carries the song-change energy ripple (0.6 s) and the first-light reveal (1.0 s). The effect is `AuroraField` (CrannyEffects) with its energy budget: ≤ 30 fps on
// AC, ≤ 20 on battery, a static halo in Low Power Mode, paused while closed, hidden, occluded or behind a
// full-screen app, and a resting frame under Reduce Motion.
import CrannyCore
import CrannyEffects
import SwiftUI

struct NookLightLayer: View {
    @Environment(\.cranny) private var theme
    @Environment(\.notchDelight) private var delight
    @State private var ripple: Double = 0
    @State private var firstLight: Double = 1
    let model: NotchSceneModel
    let registry: ModuleRegistry

    var body: some View {
        let level = theme.effectiveAmbience
        let budget = registry.services.environment.effectBudget(
            isOpen: model.phase == .open, isOnScreen: model.isVisibleOnScreen,
            reduceMotion: theme.reduceMotion || theme.motion == .instant)
        let energy = min((registry.services.nowPlaying?.audioEnergy ?? 0) + ripple, 1)
        let revealing = delight?.moment == .firstLight && !theme.reduceMotion
        AuroraField(palette: model.ambient, level: level, energy: energy, budget: budget)
            .mask { if revealing { FirstLightMask(progress: firstLight) } else { Color.white } }
            .overlay { if revealing { FirstLightCrest(progress: firstLight, glow: model.ambient.glow1, cap: Glow.ambientAlphaCap(max(level, .subtle))) } }
            .animation(theme.animation(.colorShift), value: model.ambient)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onChange(of: delight?.serial) { _, _ in play(delight) }
    }

    private func play(_ playback: DelightPlayback?) {
        guard let playback, !theme.reduceMotion, theme.motion != .instant else { return }
        switch playback.moment {
        case .songRipple:
            // The fallback's energy pulse: energy + 0.5 · (1 − t/0.6)² (DESIGN.md §5.6 `songRipple`).
            ripple = 0.5
            withAnimation(DelightMotion.ripple(lifetime: playback.lifetime)) { ripple = 0 }
        case .firstLight:
            firstLight = 0
            withAnimation(DelightMotion.firstLight(lifetime: playback.lifetime)) { firstLight = 1 }
        default:
            break
        }
    }
}

#Preview("Light · Vivid, timer palette") {
    let (model, registry) = previewScene(.open, variant: .lit)
    model.ambient = .timer
    return NotchCanvasView(model: model, registry: registry)
        .frame(width: model.layout.canvasSize.width, height: 260)
        .background(Color(white: 0.25))
}
