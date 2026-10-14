// CrannyNotchUI/Choreography/DelightPlayer.swift — plays `NotchSceneModel.delight` once per `delightSerial`
// (DESIGN.md §5.5, ARCHITECTURE.md §4.6 step 7). The owner applies the caps (one at a time, not paused, not in
// full screen, not under Instant); this file decides which moment is drawn and for how long. CrannyEffects
// draws them (`EmberBurst`, `ChargeSweep`, `FirstLight`, `songChangeRipple`, `LiquidNeck`); under Calm and Reduce
// Motion they draw their reduced variants (`drawsReducedVariant`: static fade, static ember glow, instant rim, no
// ripple, no gulp). The gulp is NotchUI's own shape motion. Each moment lives ≤ 1 s and is then removed: no clock
// runs outside a moment.
import CrannyCore
import Foundation
import SwiftUI

/// The moment playing on this canvas, if any. Pure value: the subviews that draw a moment read it from the
/// environment (`\.notchDelight`) — the ember below the shape, the rim sweep, the light layer's ripple and
/// first light, the shape's gulp — and start their view once per `serial`.
nonisolated struct DelightPlayback: Equatable, Sendable {
    var moment: DelightMoment
    var serial: Int

    /// Lifetime of each moment (DESIGN.md §5.5–§5.6; CrannyEffects' durations, checked by the tests).
    static func lifetime(of moment: DelightMoment) -> Double {
        switch moment {
        case .emberBurst: 0.9
        case .chargeSweep: 0.8
        case .songRipple: 0.6
        case .firstLight: 1.0
        case .gulp: 0.25
        }
    }

    var lifetime: Double { Self.lifetime(of: moment) }

    /// A serial plays once: only a serial newer than the last one played, with a moment set. Serials seen when
    /// the canvas appears are history and never replay (`lastPlayed` starts at the scene's serial).
    static func shouldPlay(moment: DelightMoment?, serial: Int, lastPlayed: Int) -> Bool {
        moment != nil && serial > lastPlayed
    }

    /// Whether a moment drawn with a clock (ember burst, charge sweep) is drawn at all: not while the panel is
    /// covered, the screen is locked, the displays sleep or a full-screen app is in front, so no clock runs for a
    /// moment nobody sees. Neither Low Power (the moment then draws its SwiftUI design, DESIGN.md §5.5 "Engines")
    /// nor a closed Nook stops one. Pure.
    static func isSeen(_ budget: EffectBudget) -> Bool {
        budget.onScreen && !budget.fullScreenFront
    }

    /// Whether this canvas draws a moment's reduced variant (DESIGN.md §5.5, last column: static fade, static ember
    /// glow, instant rim, colour only, no gulp): under Reduce Motion and under Calm. Instant too, for a stage that
    /// plays a moment anyway (the shell schedules none under Instant). The ambient light itself is not a moment: it
    /// keeps moving under Calm. Pure.
    static func drawsReducedVariant(_ theme: CrannyTheme) -> Bool {
        theme.reduceMotion || theme.motion == .calm || theme.motion == .instant
    }
}

extension EnvironmentValues {
    /// The delight playing on this canvas (nil = none).
    @Entry var notchDelight: DelightPlayback? = nil
}

/// Watches the scene's serial, starts a playback and ends it after its lifetime. Applied once, at the canvas body.
struct DelightPlayer: ViewModifier {
    let moment: DelightMoment?
    let serial: Int
    @State private var lastPlayed: Int?
    @State private var playback: DelightPlayback?

    func body(content: Content) -> some View {
        content
            .environment(\.notchDelight, playback)
            .onAppear { if lastPlayed == nil { lastPlayed = serial } }
            .onChange(of: serial) { _, newSerial in
                guard DelightPlayback.shouldPlay(moment: moment, serial: newSerial, lastPlayed: lastPlayed ?? newSerial - 1),
                      let moment else { return }
                lastPlayed = newSerial
                playback = DelightPlayback(moment: moment, serial: newSerial)
            }
            .task(id: playback?.serial) {
                guard let current = playback else { return }
                try? await Task.sleep(for: .seconds(current.lifetime))
                guard !Task.isCancelled, playback?.serial == current.serial else { return }
                playback = nil
            }
    }
}

extension View {
    /// Plays `moment` once per new `serial` (see `DelightPlayer`).
    func delightPlayer(moment: DelightMoment?, serial: Int) -> some View {
        modifier(DelightPlayer(moment: moment, serial: serial))
    }
}

// MARK: - The gulp (file caught): height −3 pt, spring back over 0.25 s

/// Shape height offset while a gulp plays (DESIGN.md §5.5). Calm and Reduce Motion: none (the owner's haptic stays).
struct GulpModifier: ViewModifier {
    @Environment(\.cranny) private var theme
    @Environment(\.notchDelight) private var delight
    @Binding var depth: CGFloat

    func body(content: Content) -> some View {
        content.onChange(of: delight?.serial) { _, _ in
            guard let delight, delight.moment == .gulp, !DelightPlayback.drawsReducedVariant(theme) else { return }
            withAnimation(DelightMotion.gulpSwallow) { depth = -Gulp.depth } completion: {
                withAnimation(DelightMotion.gulpRecover) { depth = 0 }
            }
        }
    }
}

nonisolated enum Gulp {
    /// How far the shape's bottom edge rises.
    static let depth = CrannyMotion.Delight.gulpDepth
    /// Down in 0.07 s, back over the rest of the 0.25-s moment.
    static let swallow = CrannyMotion.Delight.gulpSwallowDuration
    static let recover = CrannyMotion.Delight.gulpRecoverDuration
}
