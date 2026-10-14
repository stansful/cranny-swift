// CrannyMedia/Visualizer/LiveSpectrum.swift — drives the Live visualizer while it is allowed to run: the audio
// tap feeds the ring, a main-actor loop analyzes the latest 1024 samples at the visualizer's frame rate (≤ 30 fps,
// ≤ 20 on battery) and hands 5 bar levels + the smoothed energy to the engine. One sleep per frame to a deadline
// (no Timer, no TimelineView); the loop stops with the tap.
import CrannyCore
import Foundation
import os

private nonisolated let log = Log.logger(.media)

@available(macOS 14.2, *)
@MainActor final class LiveSpectrum {
    /// What one frame produced.
    struct Frame: Equatable {
        var bars: [Double]
        var energy: Double
        /// False while the tap delivers digital silence (denied permission, muted output, a quiet passage).
        var hasAudio: Bool
    }

    private let tap = SystemAudioTap()
    private let analyzer = SpectrumAnalyzer()
    private var follower = EnergyFollower()
    private var samples = [Float](repeating: 0, count: 1024)
    private var loop: Task<Void, Never>?
    private let onFrame: @MainActor (Frame) -> Void

    init(onFrame: @escaping @MainActor (Frame) -> Void) { self.onFrame = onFrame }

    var isRunning: Bool { loop != nil }

    /// Starts the tap (prompting the first time) and the analysis loop at `interval` seconds per frame.
    func start(interval: Double) throws(SystemAudioTapError) {
        guard loop == nil else { return }
        try tap.start()
        log.info("live visualizer: tap running")
        let interval = max(interval, 1.0 / 60)
        loop = Task { [weak self] in
            let clock = ContinuousClock()
            var deadline = clock.now
            while !Task.isCancelled {
                let next = deadline.advanced(by: .seconds(interval))
                deadline = next > clock.now ? next : clock.now.advanced(by: .seconds(interval))
                do { try await Task.sleep(until: deadline, tolerance: .seconds(interval / 8), clock: clock) } catch { return }
                self?.tick(dt: interval)
            }
        }
    }

    func stop() {
        loop?.cancel()
        loop = nil
        if tap.isRunning { log.info("live visualizer: tap stopped") }
        tap.stop()
        follower = EnergyFollower()
    }

    private func tick(dt: Double) {
        guard let analyzer else { return }
        samples.withUnsafeMutableBufferPointer { _ = tap.ring.latest(into: $0) }
        let rms = samples.withUnsafeBufferPointer { buffer -> Float in
            analyzer.analyze(buffer)
            return SpectrumAnalyzer.rms(buffer)
        }
        let energy = follower.update(rms: Double(rms), dt: dt)
        onFrame(Frame(bars: analyzer.barLevels, energy: energy, hasAudio: rms > 1e-5))
    }
}
