// CrannyEffects/Ambient/AmbientEnergySource.swift — the live audio energy the light reads once per frame it draws.
//
// Energy changes up to 30 times a second while the Live visualizer runs. Handed to `AmbientLayer` as a value, each
// change re-evaluated the light's SwiftUI views and gave the Metal layer a new state, although the layer's own clock
// draws at the budget's rate anyway. With a source the Metal layer samples the energy in each frame it draws, outside
// SwiftUI, so an energy change costs nothing until the next frame; the SwiftUI paths sample it in each frame of their
// `EffectClock`. A paused light draws only when an input changes, and then with the energy of that moment.
//
// Two kinds: a shared `AudioEnergyLevel` (CrannyMedia's), which the Metal layer's render thread reads itself
// (AmbientFrameLoop.swift), and a main-actor closure, for which that layer draws its steady frames on the main thread.
import CrannyCore

/// Where the light reads the live audio energy (0…1), at most once per frame it draws.
public struct AmbientEnergySource {
    private let read: @MainActor () -> Double
    /// The level behind `read`, when there is one: readable on the Metal layer's render thread.
    let level: AudioEnergyLevel?

    /// `read` runs on the main actor once per frame; keep it cheap. The Metal layer calls it outside any view
    /// update, so reading an `@Observable` property there creates no dependency. Its steady frames are then drawn on
    /// the main thread; prefer `init(_: AudioEnergyLevel)` where the source keeps a level.
    public init(_ read: @escaping @MainActor () -> Double) {
        self.read = read
        level = nil
    }

    /// A source any thread can read: the Metal layer samples it on its render thread, without the main actor.
    public init(_ level: AudioEnergyLevel) {
        self.read = { level.current }
        self.level = level
    }

    /// The energy now, clamped to 0…1.
    func sample() -> Double { Self.clamped(read()) }

    nonisolated static func clamped(_ energy: Double) -> Double { min(max(energy, 0), 1) }
}
