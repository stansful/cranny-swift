// CrannyEffects/Ambient/AmbientFieldView.swift — draws one ambient effect (aurora, motes, tide, halo) on the path
// `AmbientPath.resolve` picks: the dedicated Metal layer, the SwiftUI stitchable shader, the SwiftUI fallback or
// the static Low Power halo (DESIGN.md §5.3, §5.6). The public fields and `AmbientLayer` are thin wrappers.
//
// Inputs from around the view: First light's reveal and the song-change ripple (EffectEnvironment.swift). The
// Metal layer receives them as uniforms; the SwiftUI paths apply them as masks and a distortion.
import CrannyCore
import Foundation
import SwiftUI

struct AmbientFieldView: View, Animatable {
    var effect: AmbientEffect
    var palette: AmbientPalette
    var level: AmbienceLevel
    var energy: Double
    /// 0…1: how far the light has risen from the bottom edge (`ambientIn` / `ambientOut`, AmbientLayer).
    var fill: Double
    var budget: EffectBudget
    var restingTime: Double
    var halo: HaloPlacement = .ambient
    /// Live energy sampled per frame instead of `energy` (`AmbientEnergySource`).
    var energySource: AmbientEnergySource? = nil

    @Environment(\.displayScale) private var displayScale
    @Environment(\.ambientReveal) private var reveal
    @Environment(\.ambientRippleStart) private var rippleStart
    @Environment(\.effectRendering) private var rendering

    nonisolated var animatableData: AnimatablePair<AmbientPalette.Vector, AnimatablePair<Double, Double>> {
        get { .init(palette.vector, .init(energy, fill)) }
        set { palette.vector = newValue.first; energy = newValue.second.first; fill = newValue.second.second }
    }

    var body: some View {
        let budget = EffectsQA.adjusted(budget)
        let layerAllowed = rendering == .automatic && ShaderEffects.allowsLayer && AmbientLayerSupport.shared.isUsable
        let path = AmbientPath.resolve(budget: budget, shadersAvailable: ShaderEffects.isAvailable,
                                       layerAllowed: layerAllowed)
        Group {
            if path == .layer {
                AmbientMetalLayer(state: layerState(budget), energySource: energySource)
            } else if path == .staticHalo {
                HaloFallback(glow: palette.glow1, level: level, placement: halo)
                    .modifier(AmbientMasks(fill: fill, reveal: reveal, reduceMotion: budget.reduceMotion))
            } else {
                clocked(path, budget: budget)
                    .modifier(AmbientMasks(fill: fill, reveal: reveal, reduceMotion: budget.reduceMotion))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func layerState(_ budget: EffectBudget) -> AmbientLayerState {
        AmbientLayerState(effect: effect, glows: palette.glows, energy: energy, level: level, fill: fill,
                          reveal: reveal, rippleStart: rippleStart, halo: halo,
                          interval: budget.minimumInterval, restingTime: restingTime)
    }

    /// The SwiftUI paths, timed by `EffectClock` at the budget's interval (paused: the last frame stays).
    private func clocked(_ path: AmbientPath, budget: EffectBudget) -> some View {
        EffectClock(minimumInterval: budget.minimumInterval) { date in
            let time = EffectTiming.ambientTime(date, budget: budget, restingTime: restingTime)
            let ripple = budget.reduceMotion ? nil : Ripple.elapsed(since: rippleStart, at: date)
            let energy = Ripple.energy(energySource?.sample() ?? energy, elapsed: ripple)
            if path == .shader {
                AmbientShader(effect: effect, glows: palette.glows, level: level, energy: energy, time: time,
                              halo: halo, displayScale: displayScale)
                    .modifier(RippleDistortion(elapsed: ripple))
            } else {
                AmbientFallback(effect: effect, palette: palette, level: level, energy: energy, time: time, halo: halo)
            }
        }
    }
}

// MARK: - Shader and fallback dispatch

/// The stitchable function of each ambient effect on a `Rectangle` the size of the layer, then the dither.
struct AmbientShader: View {
    var effect: AmbientEffect
    var glows: [RGB]
    var level: AmbienceLevel
    var energy: Double
    var time: Double
    var halo: HaloPlacement = .ambient
    var displayScale: CGFloat

    var body: some View {
        Rectangle()
            .colorEffect(shader)
            .crannyDithered(scale: displayScale, isEnabled: effect != .motes)   // specks need no dither
    }

    private var shader: Shader {
        let library = ShaderEffects.library
        let stops = Shader.Argument.colorArray(glows.map { $0.color(1) })
        let cap = Shader.Argument.float(Glow.ambientAlphaCap(level))
        let intensity = Shader.Argument.float(level.intensity)
        switch effect {
        case .aurora:
            return library.auroraField(.boundingRect, .float(time), stops, .float(energy), intensity, cap)
        case .tide:
            return library.tideField(.boundingRect, .float(time), stops, .float(energy), intensity, cap)
        case .motes:
            return library.motesField(.boundingRect, .float(time), stops, .float(energy), intensity, cap)
        case .halo:
            return library.haloGlow(.boundingRect, .float2(halo.center.x, halo.center.y), .float(halo.radius),
                                    .color((glows.first ?? .black).color(1)), cap)
        }
    }
}

/// The SwiftUI fallback of each ambient effect (DESIGN.md §5.3, App. B.1).
struct AmbientFallback: View {
    var effect: AmbientEffect
    var palette: AmbientPalette
    var level: AmbienceLevel
    var energy: Double
    var time: Double
    var halo: HaloPlacement = .ambient

    var body: some View {
        switch effect {
        case .aurora: AuroraFallback(palette: palette, level: level, energy: energy, time: time)
        case .motes: MotesFallback(glows: palette.glows, level: level, energy: energy, time: time)
        case .tide: TideFallback(glows: palette.glows, level: level, energy: energy, time: time)
        case .halo: HaloFallback(glow: palette.glow1, level: level, placement: halo)
        }
    }
}

// MARK: - Masks and the ripple on the SwiftUI paths

/// Fill (the light rises from the bottom edge; an opacity fade under Reduce Motion) and First light's reveal.
/// Applied only while they show something, so the settled light renders without an offscreen pass.
struct AmbientMasks: ViewModifier {
    var fill: Double
    var reveal: AmbientReveal?
    var reduceMotion: Bool

    func body(content: Content) -> some View {
        if fill >= 1, reveal == nil {
            content
        } else {
            content
                .mask {
                    if reduceMotion {
                        Rectangle().opacity(fill)
                    } else {
                        FillMask(fill: fill)
                    }
                }
                .mask { RevealMask(reveal: reveal) }
        }
    }
}

/// `cranny::fillMask` as a gradient: clear above the rising edge, opaque below, a 25 % soft edge.
struct FillMask: View {
    var fill: Double

    var body: some View {
        let soft = 0.25
        let edge = 1 - min(max(fill, 0), 1) * (1 + soft)
        // The gradient runs from the edge (clear) to edge + soft (opaque), in unit coordinates of the layer.
        LinearGradient(stops: (0...4).map { i in
                           let x = Double(i) / 4
                           return Gradient.Stop(color: .white.opacity(Easing.easeInOut(x)), location: x)
                       },
                       startPoint: UnitPoint(x: 0.5, y: edge), endPoint: UnitPoint(x: 0.5, y: edge + soft))
    }
}

/// `cranny::revealMask` as a radial gradient (white inside `radius − feather`, clear beyond `radius`).
struct RevealMask: View {
    var reveal: AmbientReveal?

    var body: some View {
        if let reveal, reveal.radius > 0 {
            let inner = max(reveal.radius - reveal.feather, 0)
            RadialGradient(stops: (0...4).map { i in
                               let x = Double(i) / 4
                               return Gradient.Stop(color: .white.opacity(1 - Easing.easeInOut(x)), location: x)
                           },
                           center: reveal.center, startRadius: inner, endRadius: max(reveal.radius, inner + 0.5))
        } else if reveal != nil {
            Color.clear
        } else {
            Rectangle()
        }
    }
}

/// `songRipple` as a `.distortionEffect` on the SwiftUI shader path, centred on the camera (top centre).
struct RippleDistortion: ViewModifier {
    var elapsed: Double?

    func body(content: Content) -> some View {
        let t = elapsed ?? 0
        let active = elapsed != nil
        content.visualEffect { effect, proxy in
            effect.distortionEffect(
                ShaderEffects.library.songRipple(.float2(proxy.size.width / 2, 0), .float(t), .float(Ripple.amplitude),
                                                 .float(Ripple.wavelength), .float(Ripple.speed)),
                maxSampleOffset: CGSize(width: Ripple.amplitude, height: Ripple.amplitude), isEnabled: active)
        }
    }
}

// MARK: - Previews

#Preview("Ambient paths · layer, SwiftUI shader, fallback") {
    VStack(spacing: Space.s) {
        AmbientFieldView(effect: .aurora, palette: .afterglow, level: .vivid, energy: 0, fill: 1,
                         budget: .previewRunning, restingTime: 7.3)
        AmbientFieldView(effect: .aurora, palette: .afterglow, level: .vivid, energy: 0, fill: 1,
                         budget: .previewRunning, restingTime: 7.3)
            .ambientLightRendering(.inline)
        AmbientFieldView(effect: .aurora, palette: .afterglow, level: .vivid, energy: 0, fill: 1,
                         budget: .previewReduceMotion, restingTime: 7.3)
    }
    .frame(width: 656, height: 380)
    .background(.black)
    .crannyThemeRoot(CrannyTheme())
}

#Preview("Ambient fill · half risen") {
    AmbientFieldView(effect: .tide, palette: .timer, level: .vivid, energy: 0.5, fill: 0.5, budget: .previewRunning,
                     restingTime: 7.3)
        .frame(width: 656, height: 170)
        .background(.black)
        .crannyThemeRoot(CrannyTheme())
}
