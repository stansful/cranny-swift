// CrannyMedia/Visualizer/SpectrumAnalyzer.swift — FFT 1024 → 24 log-spaced bands → 5 bars, plus RMS, for the
// opt-in Live visualizer (ARCHITECTURE.md §6.6, R2 §8: ≈ 1.5 µs per frame). Allocation-free after `init`.
// Not thread-safe: one analyzer per consumer (the live spectrum's main-actor loop). Tested with synthetic buffers.
import Accelerate
import Foundation

nonisolated final class SpectrumAnalyzer {
    let size: Int
    let bandCount: Int
    private let setup: vDSP_DFT_Setup
    private var window: [Float]
    private var frame: [Float], evens: [Float], odds: [Float], outReal: [Float], outImag: [Float], magnitudes: [Float]
    private let edges: [Int]            // FFT bin boundaries of each band
    /// 0…1 per band, smoothed (fast attack, slow release).
    private(set) var bands: [Float]

    /// nil when vDSP cannot build a DFT of `size` (must be a supported power of two, e.g. 1024).
    init?(size: Int = 1024, bands: Int = 24, sampleRate: Double = 48_000, minHz: Double = 40, maxHz: Double = 16_000) {
        guard size >= 64, bands > 0, let setup = vDSP_DFT_zrop_CreateSetup(nil, vDSP_Length(size), .FORWARD) else { return nil }
        self.size = size
        self.bandCount = bands
        self.setup = setup
        window = vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized, count: size, isHalfWindow: false)
        frame = .init(repeating: 0, count: size)
        evens = .init(repeating: 0, count: size / 2)
        odds = evens; outReal = evens; outImag = evens; magnitudes = evens
        self.bands = .init(repeating: 0, count: bands)
        let binHz = sampleRate / Double(size)
        edges = (0...bands).map { i in
            let hz = minHz * pow(maxHz / minHz, Double(i) / Double(bands))      // log-spaced
            return max(1, min(size / 2 - 1, Int(hz / binHz)))
        }
    }

    deinit { vDSP_DFT_DestroySetup(setup) }

    /// Analyzes the most recent `size` mono samples (`samples.count` must equal `size`).
    func analyze(_ samples: UnsafeBufferPointer<Float>, attack: Float = 0.6, release: Float = 0.12) {
        guard samples.count == size, let input = samples.baseAddress else { return }
        let n = size
        frame.withUnsafeMutableBufferPointer { f in
            guard let fp = f.baseAddress else { return }
            vDSP_vmul(input, 1, window, 1, fp, 1, vDSP_Length(n))
            // zrop takes the real signal split into even (real part) and odd (imaginary part) samples.
            evens.withUnsafeMutableBufferPointer { re in
                odds.withUnsafeMutableBufferPointer { im in
                    guard let rp = re.baseAddress, let ip = im.baseAddress else { return }
                    var split = DSPSplitComplex(realp: rp, imagp: ip)
                    fp.withMemoryRebound(to: DSPComplex.self, capacity: n / 2) {
                        vDSP_ctoz($0, 2, &split, 1, vDSP_Length(n / 2))
                    }
                }
            }
        }
        vDSP_DFT_Execute(setup, evens, odds, &outReal, &outImag)
        outReal.withUnsafeMutableBufferPointer { re in
            outImag.withUnsafeMutableBufferPointer { im in
                guard let rp = re.baseAddress, let ip = im.baseAddress else { return }
                var z = DSPSplitComplex(realp: rp, imagp: ip)
                vDSP_zvmags(&z, 1, &magnitudes, 1, vDSP_Length(n / 2))
            }
        }
        // Reference: a full-scale sine through the window peaks near (n / 4)^2 in zrop's packed scaling.
        let reference = Float(n * n) / 16
        for b in 0..<bandCount {
            let lo = edges[b], hi = max(edges[b] + 1, edges[b + 1])
            var peak: Float = 0
            magnitudes.withUnsafeBufferPointer { m in
                guard let mp = m.baseAddress else { return }
                vDSP_maxv(mp + lo, 1, &peak, vDSP_Length(hi - lo))
            }
            let db = 10 * log10f(peak / reference + 1e-12)          // power → dB
            let target = max(0, min(1, (db + 60) / 60))              // −60 dB … 0 dB → 0 … 1
            let k = target > bands[b] ? attack : release
            bands[b] += (target - bands[b]) * k
        }
    }

    /// The 24 bands folded into the 5 visualizer bars (bass … treble): the loudest band of each group.
    var barLevels: [Double] {
        Self.fold(bands.map(Double.init), into: SyntheticSpectrum.barCount)
    }

    /// Root mean square of `samples` (0 … 1 for full-scale audio).
    static func rms(_ samples: UnsafeBufferPointer<Float>) -> Float {
        guard let base = samples.baseAddress, !samples.isEmpty else { return 0 }
        var value: Float = 0
        vDSP_rmsqv(base, 1, &value, vDSP_Length(samples.count))
        return value
    }

    /// Splits `levels` into `count` contiguous groups (lower groups narrower, like the ear) and takes each max.
    static func fold(_ levels: [Double], into count: Int) -> [Double] {
        guard !levels.isEmpty, count > 0 else { return Array(repeating: 0, count: max(count, 0)) }
        // Group boundaries on a gentle power curve: 24 bands → 3, 4, 5, 6, 6.
        let bounds = (0...count).map { i in Int((Double(levels.count) * pow(Double(i) / Double(count), 1.25)).rounded()) }
        return (0..<count).map { g in
            let lo = min(bounds[g], levels.count - 1), hi = max(min(bounds[g + 1], levels.count), lo + 1)
            return levels[lo..<hi].max() ?? 0
        }
    }
}

/// Smoothed loudness for the light layer: 60 ms attack, 300 ms release (ARCHITECTURE.md §3.9 `audioEnergy`).
nonisolated struct EnergyFollower: Equatable, Sendable {
    static let attack = 0.060
    static let release = 0.300
    private(set) var value: Double = 0

    /// Feeds one RMS reading taken `dt` seconds after the previous one; returns the smoothed value (0…1).
    mutating func update(rms: Double, dt: Double) -> Double {
        let target = min(max(rms * 2.5, 0), 1)              // music RMS rarely exceeds 0.4
        let tau = target > value ? Self.attack : Self.release
        let k = dt <= 0 ? 0 : 1 - exp(-dt / tau)
        value += (target - value) * k
        return value
    }
}
