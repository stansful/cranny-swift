// CrannyNotchUI/Nook/NookLightLayer.swift — the light behind the open panel (DESIGN.md §5, ARCHITECTURE.md §10):
// CrannyEffects' `AmbientLayer` in the effect of Appearance ▸ Effect (aurora, motes or tide; the static halo under
// Low Power). It fills the frame the canvas gives it (`LightFrame`: the shape's body at its CURRENT, animating size),
// so it rides the bottom edge as the panel opens; it rises with `ambientIn`, the canvas fades it out with
// `ambientOut`, and palettes cross-fade with `colorShift`. The light's moments come from CrannyEffects too:
// `FirstLight` (the first open per session, 1.0 s) and `songChangeRipple` (0.6 s), each started by the scene's
// delight serial, which the shell has already capped (DESIGN.md §5.5). Energy budget: ≤ 30 fps on AC, ≤ 20 on
// battery, paused while closed, hidden, occluded or behind a full-screen app, a resting frame under Reduce Motion.
import CrannyCore
import CrannyEffects
import SwiftUI

struct NookLightLayer: View {
    @Environment(\.cranny) private var theme
    @Environment(\.notchDelight) private var delight
    /// Snapshots (`ImageRenderer`: tests, the gallery, `--qa-snapshot`) cannot see CrannyEffects' Metal layer, so
    /// they keep the light in SwiftUI (`ambientLightRendering(.inline)`) on its resting frame (deterministic
    /// pixels); the live panel uses the cheaper layer.
    @Environment(\.notchRendersFinalState) private var isSnapshot
    /// The first light this layer plays (its delight serial). It wraps the light from the moment it starts until
    /// the panel closes (`FirstLight` then draws only the light), so the light keeps its identity once it lands.
    /// Only a serial that arrives while this layer is on screen starts it: a layer created later never replays it.
    @State private var firstLight: Int?
    /// The last song change (its delight serial): each new value plays the ripple once.
    @State private var songChange: Int?
    let model: NotchSceneModel
    let registry: ModuleRegistry

    var body: some View {
        let level = theme.effectiveAmbience
        let budget = registry.services.environment.effectBudget(
            isOpen: model.phase == .open, isOnScreen: model.isVisibleOnScreen,
            reduceMotion: theme.reduceMotion || theme.motion == .instant || isSnapshot)   // snapshots: the resting frame
        // First light is a moment: Calm draws its static fade too, while the light itself keeps moving (DESIGN.md §4.2).
        var moment = budget
        moment.reduceMotion = budget.reduceMotion || DelightPlayback.drawsReducedVariant(theme)
        return Group {
            if let firstLight {
                FirstLight(palette: model.ambient, level: level, budget: moment) { light(level: level, budget: budget) }
                    .id(firstLight)
            } else {
                light(level: level, budget: budget)
            }
        }
        .songChangeRipple(songChange)
        .animation(theme.animation(.colorShift), value: model.ambient)
        .ambientLightRendering(isSnapshot ? .inline : .automatic)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: delight?.serial) { _, _ in start(delight) }
    }

    private func light(level: AmbienceLevel, budget: EffectBudget) -> some View {
        AmbientLayer(palette: model.ambient, level: level, effect: theme.effect,
                     energy: min(max(registry.services.nowPlaying?.audioEnergy ?? 0, 0), 1), budget: budget)
    }

    /// The light's moments; the others (ember burst, charge sweep, gulp) are drawn elsewhere on the canvas.
    private func start(_ playback: DelightPlayback?) {
        guard let playback else { return }
        switch playback.moment {
        case .firstLight: firstLight = playback.serial
        case .songRipple: songChange = playback.serial
        case .emberBurst, .chargeSweep, .gulp: break
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

#Preview("Light · Vivid, motes") {
    let (model, registry) = previewScene(.open, variant: .lit)
    model.theme.effect = .motes
    return NotchCanvasView(model: model, registry: registry)
        .frame(width: model.layout.canvasSize.width, height: 260)
        .background(Color(white: 0.25))
}
