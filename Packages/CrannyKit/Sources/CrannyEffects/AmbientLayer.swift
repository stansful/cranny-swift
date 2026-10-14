// CrannyEffects/AmbientLayer.swift — the light layer behind the open panel's grid (DESIGN.md §5, §4.3).
// It picks the effect (Halo under Low Power / thermal), fills from the bottom edge when the panel opens
// (`ambientIn`) and drains when it closes (`ambientOut`). Callers frame it to the shape's CURRENT bounds, so the
// light rises with the bottom edge as the panel opens. Nothing here reads settings: the caller passes the values.
import CrannyCore
import SwiftUI

/// The ambient light of the open panel: aurora, motes or tide in `palette`, or the static halo under Low Power.
///
/// - Draws nothing at `.off`; never takes clicks; hidden from VoiceOver.
/// - Runs at `budget`'s frame rate (≤ 30 fps on AC, ≤ 20 on battery), pauses with the budget, freezes a resting
///   frame under Reduce Motion, and uses the dedicated Metal layer whenever shaders run (no SwiftUI work per frame).
/// - Wrap it in `FirstLight` for the first open of a session, and apply `songChangeRipple(_:)` around it for track
///   changes.
/// - Frame it to the shape's current bounds: while the size changes (the open and close morph) each layout pass
///   draws one synchronous frame at the new size; at rest it draws only at the budget's frame rate.
/// - Rendering: a dedicated Metal layer whenever shaders run, which `ImageRenderer`, `cacheDisplay`,
///   `drawingGroup()` and shader effects over the light cannot see; `ambientLightRendering(.inline)` keeps it in SwiftUI.
public struct AmbientLayer: View, Animatable {
    /// The light's colours; animate a change with `CrannyMotion.Kind.colorShift` to cross-fade.
    public var palette: AmbientPalette
    /// Settings ▸ Appearance ▸ Ambient light (the theme's `effectiveAmbience`).
    public var level: AmbienceLevel
    /// Settings ▸ Appearance ▸ Effect. Low Power / thermal turns it into the static halo.
    public var effect: AmbientEffect
    /// 0…1: real audio RMS with permission, else 0. Unused while `energySource` is set.
    public var energy: Double
    /// Live energy read once per frame (the Metal layer samples it outside SwiftUI); nil: `energy`.
    public var energySource: AmbientEnergySource?
    /// Frame rate, pause and path. `isOpen` also drives the fill (true) and the drain (false).
    public var budget: EffectBudget

    @Environment(\.cranny) private var theme
    @State private var fill: Double = 0

    /// The light layer for `effect` in `palette` at `level`. Pass a live `energySource` instead of a changing `energy`
    /// value, so an energy change does not re-evaluate the caller's views.
    public init(palette: AmbientPalette, level: AmbienceLevel, effect: AmbientEffect, energy: Double, budget: EffectBudget,
                energySource: AmbientEnergySource? = nil) {
        self.palette = palette; self.level = level; self.effect = effect; self.energy = energy; self.budget = budget
        self.energySource = energySource
    }

    /// Palette and energy, so a track change cross-fades the light.
    public nonisolated var animatableData: AnimatablePair<AmbientPalette.Vector, Double> {
        get { .init(palette.vector, energy) }
        set { palette.vector = newValue.first; energy = newValue.second }
    }

    public var body: some View {
        if level != .off {
            let budget = EffectsQA.adjusted(budget)
            AmbientFieldView(effect: budget.effective(effect), palette: palette, level: level, energy: energy,
                             fill: fill, budget: budget, restingTime: 7.3, energySource: energySource)
                .onAppear { setFilled(budget.isOpen) }
                .onChange(of: budget.isOpen) { _, isOpen in setFilled(isOpen) }
        }
    }

    /// `ambientIn` (easeOut 0.5 s after 0.1 s) rises from the bottom edge; `ambientOut` (easeIn 0.2 s) drains.
    /// Reduce Motion turns both into a 0.2-s fade; Instant shows the end state at once.
    private func setFilled(_ filled: Bool) {
        let target: Double = filled ? 1 : 0
        guard fill != target else { return }
        withAnimation(theme.animation(filled ? .ambientIn : .ambientOut)) { fill = target }
    }
}

// MARK: - Previews

#Preview("Ambient layer · each effect") {
    VStack(spacing: Space.s) {
        ForEach(AmbientEffect.allCases, id: \.self) { effect in
            AmbientLayer(palette: .afterglow, level: .subtle, effect: effect, energy: 0.2, budget: .previewRunning)
                .frame(width: 656, height: 120)
        }
    }
    .padding(Space.m)
    .background(.black)
    .crannyThemeRoot(CrannyTheme())
}

#Preview("Ambient layer · Low Power halo") {
    AmbientLayer(palette: .timer, level: .vivid, effect: .aurora, energy: 0, budget: .previewLowPower)
        .frame(width: 656, height: 170)
        .background(.black)
        .crannyThemeRoot(CrannyTheme())
}
