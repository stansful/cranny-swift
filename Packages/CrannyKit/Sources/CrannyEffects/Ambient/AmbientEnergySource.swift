// CrannyEffects/Ambient/AmbientEnergySource.swift — the live audio energy the light reads once per frame it draws.
//
// Energy changes up to 30 times a second while the Live visualizer runs. Handed to `AmbientLayer` as a value, each
// change re-evaluated the light's SwiftUI views and gave the Metal layer a new state, although the layer's own clock
// draws at the budget's rate anyway. With a source the Metal layer samples the energy in each frame it draws, outside
// SwiftUI, so an energy change costs nothing until the next frame; the SwiftUI paths sample it in each frame of their
// `EffectClock`. A paused light draws only when an input changes, and then with the energy of that moment.
import CrannyCore

/// Where the light reads the live audio energy (0…1), at most once per frame it draws.
public struct AmbientEnergySource {
    private let read: @MainActor () -> Double

    /// `read` runs on the main actor once per frame; keep it cheap. The Metal layer calls it outside any view
    /// update, so reading an `@Observable` property there creates no dependency.
    public init(_ read: @escaping @MainActor () -> Double) { self.read = read }

    /// The energy now, clamped to 0…1.
    func sample() -> Double { min(max(read(), 0), 1) }
}
