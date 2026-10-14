// CrannyAppShell/State/DelightScheduler.swift — the caps on one-shot delight moments (ARCHITECTURE.md §4.6
// step 7, DESIGN.md §5.5): one at a time, none while paused or with a full-screen app in front, none on a hidden
// panel (locked, asleep, hidden by policy: nobody would see it, §9.2), none under Motion ▸ Instant. Calm and Reduce
// Motion do not veto a moment: CrannyNotchUI draws its reduced variant (static fade, static ember glow, instant rim).
// A moment whose reduced variant draws nothing (the song ripple is colour only, carried by the palette cross-fade;
// the gulp is gone, its haptic stays) is not scheduled then, so it never keeps the stage from one that shows.
// Pure; the coordinator writes the winner into the pointer display's scene.
import CrannyCore
import Foundation

nonisolated struct DelightScheduler: Equatable, Sendable {
    /// The facts that may veto a moment.
    struct Gate: Equatable, Sendable {
        var paused = false
        var fullScreenInFront = false
        /// The target panel is hidden (content alpha 0): a moment there would be invisible work.
        var hidden = false
        var motion: MotionPersonality = .standard
        var reduceMotion = false

        /// Nothing vetoes a moment: Instant is the only motion setting that suppresses them all.
        var allowsDelight: Bool {
            !paused && !fullScreenInFront && !hidden && motion != .instant
        }

        /// Calm and Reduce Motion play the reduced variants (DESIGN.md §5.5, last column).
        var playsReducedVariant: Bool { reduceMotion || motion == .calm }
    }

    /// The moment playing now ends at this time (systemUptime); nothing else starts before.
    private(set) var busyUntil: TimeInterval = -.infinity
    /// First light plays on the first open of a session only (whether or not that open could show it).
    private(set) var hasOpened = false

    /// How long each moment occupies the stage (DESIGN.md §5.5–§5.6). The reduced variants last as long.
    static func duration(_ moment: DelightMoment) -> TimeInterval {
        switch moment {
        case .emberBurst: 0.9
        case .chargeSweep: 0.8
        case .songRipple: 0.6
        case .firstLight: 1.0
        case .gulp: NotchMachine.catchGulp
        }
    }

    /// Whether the Calm / Reduce Motion variant of `moment` draws anything (DESIGN.md §5.5): First light fades in,
    /// Timer done glows, Charger connected lights the rim at once; Song change is colour only and the gulp is gone.
    static func hasReducedVariant(_ moment: DelightMoment) -> Bool {
        switch moment {
        case .firstLight, .emberBurst, .chargeSweep: true
        case .songRipple, .gulp: false
        }
    }

    /// True when `moment` may start now; it then occupies the stage for its duration.
    mutating func request(_ moment: DelightMoment, now: TimeInterval, gate: Gate) -> Bool {
        guard gate.allowsDelight, now >= busyUntil else { return false }
        if gate.playsReducedVariant, !Self.hasReducedVariant(moment) { return false }
        busyUntil = now + Self.duration(moment)
        return true
    }

    /// The panel opened: returns true once per session, for First light.
    mutating func firstOpen() -> Bool {
        defer { hasOpened = true }
        return !hasOpened
    }
}
