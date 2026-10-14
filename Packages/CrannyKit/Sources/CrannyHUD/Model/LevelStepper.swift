// CrannyHUD/Model/LevelStepper.swift — macOS's level grid: 16 steps, ⌥⇧ quarter steps, snapping to the grid
// (R3 §1.5, ARCHITECTURE.md §7.1). Pure, so the rules are unit-tested without touching any device.
import Foundation

nonisolated enum LevelStepper {
    /// Standard steps across the whole range (DESIGN.md §10).
    static let steps = 16

    /// 1/16, or 1/64 for ⌥⇧ fine steps.
    static func stepSize(fine: Bool) -> Double { fine ? 1 / Double(steps * 4) : 1 / Double(steps) }

    /// The next level on the grid. A level between two grid points snaps to the next one in the direction of
    /// the press. Device levels come back as Float32 (7/16 can read 0.43749997), so positions within 1 % of a
    /// step count as on the grid.
    static func step(_ level: Double, up: Bool, fine: Bool) -> Double {
        let size = stepSize(fine: fine)
        let position = clamp(level) / size
        let tolerance = 0.01
        let index = up ? (position + tolerance).rounded(.down) + 1 : (position - tolerance).rounded(.up) - 1
        return clamp(index * size)
    }

    /// How the press `from` → `to` met the scale's ends, if at all.
    static func limit(from: Double, to: Double, up: Bool) -> LevelLimit? {
        let edge: LevelEdge = up ? .top : .bottom
        let end: Double = up ? 1 : 0
        guard isAt(end, to) else { return nil }
        return isAt(end, from) ? .pressedPast(edge) : .reached(edge)
    }

    /// Whole percent for display and VoiceOver ("62").
    static func percent(_ level: Double) -> Int { Int((clamp(level) * 100).rounded()) }

    static func clamp(_ level: Double) -> Double { min(max(level.isFinite ? level : 0, 0), 1) }

    private static func isAt(_ end: Double, _ level: Double) -> Bool { abs(clamp(level) - end) < 0.0005 }
}
