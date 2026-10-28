// CrannyNotchUI/Nook/NookLightLayer.swift — the light behind the open panel (DESIGN.md §5, ARCHITECTURE.md §10):
// CrannyEffects' `AmbientLayer` in the effect of Appearance ▸ Effect (aurora, motes or tide; the static halo under
// Low Power). It fills the frame the canvas gives it (`LightFrame`: the shape's body at its CURRENT, animating size),
// so it rides the bottom edge as the panel opens; it rises with `ambientIn`, the canvas fades it out with
// `ambientOut`, and palettes cross-fade with `colorShift` (Appearance ▸ Quality ▸ Efficient: the Core Animation light
// cross-fades them itself, DESIGN.md §5.7). The light's moments come from CrannyEffects too:
// `FirstLight` (the first open per session, 1.0 s) and `songChangeRipple` (0.6 s), each started by the scene's
// delight serial, which the shell has already capped (DESIGN.md §5.5). Energy budget: ≤ 30 fps on AC, ≤ 20 on
// battery, paused while closed, hidden, occluded or behind a full-screen app, a resting frame under Reduce Motion.
// Live audio energy changes up to 30 times a second: no view reads it. The light samples it in each frame it draws
// (`EnergizedLight`, `AmbientEnergySource`), so those changes re-evaluate nothing, and a frozen light ignores them.
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
        // Efficient's Core Animation light cross-fades palettes itself (outside the app, in the window server); a
        // SwiftUI animation would hand it a new palette on every frame instead.
        .animation(fadesInLayer(budget) ? nil : theme.animation(.colorShift), value: model.ambient)
        .ambientLightRendering(isSnapshot ? .inline : .automatic)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: delight?.serial) { _, _ in start(delight) }
    }

    /// Whether the light on screen is Efficient's Core Animation light (snapshots and Low Power's halo stay in SwiftUI),
    /// decided as the light decides it.
    private func fadesInLayer(_ budget: EffectBudget) -> Bool {
        AmbientLayer.crossFadesPalettes(budget: budget, detail: theme.ambientDetail,
                                        rendering: isSnapshot ? .inline : .automatic)
    }

    private func light(level: AmbienceLevel, budget: EffectBudget) -> some View {
        EnergizedLight(palette: model.ambient, level: level, effect: theme.effect, budget: budget,
                       source: registry.services.nowPlaying)
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

/// The light with the live audio energy (0…1, 0 without a source). The energy is not read here: the light samples it
/// in each frame it draws (`AmbientEnergySource`), so an energy change re-evaluates no view, this one included. A
/// source's `audioEnergyLevel` (CrannyMedia keeps one) lets the Metal layer read it on its render thread.
/// A frozen light (Reduce Motion, Motion ▸ Instant, snapshots, Low Power, a full-screen app in front) gets no source:
/// it keeps its resting frame at energy 0 instead of being redrawn with every change of the music's loudness.
private struct EnergizedLight: View {
    let palette: AmbientPalette
    let level: AmbienceLevel
    let effect: AmbientEffect
    let budget: EffectBudget
    let source: (any NowPlayingSource)?

    var body: some View {
        AmbientLayer(palette: palette, level: level, effect: effect, energy: 0, budget: budget,
                     energySource: energySource)
    }

    private var energySource: AmbientEnergySource? {
        guard let source, !budget.reduceMotion, !budget.lowPower, !budget.fullScreenFront else { return nil }
        if let level = source.audioEnergyLevel { return AmbientEnergySource(level) }
        return AmbientEnergySource { source.audioEnergy }
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
