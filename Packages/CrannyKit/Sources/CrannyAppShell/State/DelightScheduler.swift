// CrannyAppShell/State/DelightScheduler.swift — the caps on one-shot delight moments (ARCHITECTURE.md §4.6
// step 7, DESIGN.md §5.5): one at a time, none while paused or with a full-screen app in front, none under
// Calm, Instant or Reduce Motion. Pure; the coordinator writes the winner into the pointer display's scene.
import CrannyCore
import Foundation

nonisolated struct DelightScheduler: Equatable, Sendable {
    /// The facts that may veto a moment.
    struct Gate: Equatable, Sendable {
        var paused = false
        var fullScreenInFront = false
        var motion: MotionPersonality = .standard
        var reduceMotion = false

        var allowsDelight: Bool {
            !paused && !fullScreenInFront && !reduceMotion && motion != .calm && motion != .instant
        }
    }

    /// The moment playing now ends at this time (systemUptime); nothing else starts before.
    private(set) var busyUntil: TimeInterval = -.infinity
    /// First light plays on the first open of a session only (whether or not that open could show it).
    private(set) var hasOpened = false

    /// How long each moment occupies the stage (DESIGN.md §5.5–§5.6).
    static func duration(_ moment: DelightMoment) -> TimeInterval {
        switch moment {
        case .emberBurst: 0.9
        case .chargeSweep: 0.8
        case .songRipple: 0.6
        case .firstLight: 1.0
        case .gulp: NotchMachine.catchGulp
        }
    }

    /// True when `moment` may start now; it then occupies the stage for its duration.
    mutating func request(_ moment: DelightMoment, now: TimeInterval, gate: Gate) -> Bool {
        guard gate.allowsDelight, now >= busyUntil else { return false }
        busyUntil = now + Self.duration(moment)
        return true
    }

    /// The panel opened: returns true once per session, for First light.
    mutating func firstOpen() -> Bool {
        defer { hasOpened = true }
        return !hasOpened
    }
}
