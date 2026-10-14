// CrannyMedia/Visualizer/SyntheticSpectrum.swift — the default "Ambient" visualizer (ARCHITECTURE.md §6.6,
// R2 §8): an honest breathing pattern, NOT a measurement. Per bar, a sum of slow sines seeded by the track key,
// multiplied by a soft 100–120 BPM pulse. Pure and periodic, so Core Animation can loop one precomputed cycle
// (`keyframes`) in the render server with no work in the app.
import Foundation

nonisolated struct SyntheticSpectrum: Equatable, Sendable {
    static let barCount = 5
    /// Beats in one loop: every partial is a whole multiple of 1/loop, so the cycle repeats seamlessly.
    static let beatsPerLoop = 16
    /// Lowest and highest level a playing bar reaches (fractions of the bar's travel).
    static let floor = 0.12
    static let ceiling = 1.0
    /// The level of a resting (paused) bar: the 3-pt dot.
    static let restLevel = 0.0
    /// Easing back to rest after a pause (R2 §8: ≈ 400 ms).
    static let restDuration = 0.4

    let seed: UInt64
    let bpm: Double
    private let partials: [[Partial]]   // per bar
    private let pulseWeight: [Double]   // per bar: bass bars follow the beat more

    private struct Partial: Equatable, Sendable {
        var harmonic: Double            // cycles per loop
        var phase: Double
        var amplitude: Double
    }

    /// Deterministic for a track key (FNV-1a, not `hashValue`, which changes per launch).
    init(trackKey: String) { self.init(seed: Self.fnv1a(trackKey)) }

    init(seed: UInt64) {
        self.seed = seed
        var rng = SplitMix64(seed: seed)
        bpm = 100 + 5 * Double(rng.next() % 5)                 // 100, 105, 110, 115 or 120
        partials = (0..<Self.barCount).map { bar in
            (0..<3).map { k in
                // Bar 0 is slow and deep; higher bars flicker faster. 3…26 cycles per loop ≈ 0.35–3 Hz.
                let base = 3 + bar * 3 + k * 4
                return Partial(harmonic: Double(base + Int(rng.next() % 4)),
                               phase: Double(rng.next() % 10_000) / 10_000 * 2 * .pi,
                               amplitude: [0.55, 0.3, 0.15][k])
            }
        }
        pulseWeight = (0..<Self.barCount).map { 0.55 - 0.08 * Double($0) }
    }

    /// One loop in seconds (16 beats: 8 s at 120 BPM … 9.6 s at 100 BPM).
    var loopDuration: Double { Double(Self.beatsPerLoop) * 60 / bpm }

    /// Level of `bar` at `time` (seconds), in `floor…ceiling`. Periodic with `loopDuration`.
    func level(bar: Int, at time: Double) -> Double {
        guard partials.indices.contains(bar) else { return Self.floor }
        let x = time / loopDuration                               // loops
        var sum = 0.0
        for p in partials[bar] { sum += p.amplitude * sin(2 * .pi * p.harmonic * x + p.phase) }
        let wave = 0.5 + 0.5 * sum                                // ≈ 0…1
        let beat = (x * Double(Self.beatsPerLoop)).truncatingRemainder(dividingBy: 1)
        // A soft kick: rises over the first 6 % of the beat, then decays within it.
        let pulse = beat < 0.06 ? beat / 0.06 : exp(-(beat - 0.06) / 0.22)
        let w = pulseWeight[bar]
        let value = wave * (1 - w) + pulse * w * (0.6 + 0.4 * wave)
        return min(max(Self.floor + (Self.ceiling - Self.floor) * value, Self.floor), Self.ceiling)
    }

    /// One loop sampled at `fps` (first value at t = 0; the next loop starts with it again).
    func keyframes(bar: Int, fps: Double) -> [Double] {
        let count = max(Int((loopDuration * max(fps, 1)).rounded()), 2)
        return (0..<count).map { level(bar: bar, at: Double($0) / Double(count) * loopDuration) }
    }

    /// Envelope from playing (1) to rest (0) `elapsed` seconds after a pause: ease-out, 400 ms.
    static func restEnvelope(elapsed: Double) -> Double {
        guard elapsed > 0 else { return 1 }
        let t = min(elapsed / restDuration, 1)
        return pow(1 - t, 3)
    }

    static func fnv1a(_ string: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in string.utf8 { hash = (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01B3 }
        return hash
    }
}

/// Tiny deterministic PRNG (SplitMix64) for the per-track parameters.
nonisolated struct SplitMix64: Sendable {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
