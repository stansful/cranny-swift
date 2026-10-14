// CrannyMedia/Visualizer/LiveSpectrum.swift — drives the Live visualizer while it is allowed to run: the audio
// tap feeds the ring, a main-actor loop analyzes the latest 1024 samples at the visualizer's frame rate (≤ 30 fps,
// ≤ 20 on battery) and hands 5 bar levels + the smoothed energy to the engine. One sleep per frame to a deadline
// (no Timer, no TimelineView); the loop reads its interval every frame, so `retune` takes effect at the next frame
// without touching the tap. The loop stops with the tap.
import CrannyCore
import Foundation
import os

private nonisolated let log = Log.logger(.media)

@available(macOS 14.2, *)
@MainActor final class LiveSpectrum: LiveLevelSource {
    private let tap = SystemAudioTap()
    private let analyzer = SpectrumAnalyzer()
    private var follower = EnergyFollower()
    private var samples = [Float](repeating: 0, count: 1024)
    private var loop: Task<Void, Never>?
    /// Seconds per frame; read by the loop before every frame.
    private(set) var interval: Double = 1.0 / 30
    private let onFrame: @MainActor (LiveFrame) -> Void

    init(onFrame: @escaping @MainActor (LiveFrame) -> Void) { self.onFrame = onFrame }

    var isRunning: Bool { loop != nil }

    /// Never faster than 60 fps, whatever the caller asks for.
    nonisolated static func clamped(_ interval: Double) -> Double {
        interval.isFinite ? max(interval, 1.0 / 60) : 1.0 / 30
    }

    /// Starts the tap (prompting the first time) and the analysis loop at `interval` seconds per frame. Already
    /// running: retunes.
    func start(interval: Double) throws(SystemAudioTapError) {
        guard loop == nil else { retune(interval: interval); return }
        try tap.start()
        log.info("live visualizer: tap running")
        self.interval = Self.clamped(interval)
        loop = Task { [weak self] in
            let clock = ContinuousClock()
            var deadline = clock.now
            while !Task.isCancelled, let interval = self?.interval {
                let next = deadline.advanced(by: .seconds(interval))
                deadline = next > clock.now ? next : clock.now.advanced(by: .seconds(interval))
                do { try await Task.sleep(until: deadline, tolerance: .seconds(interval / 8), clock: clock) } catch { return }
                self?.tick(dt: interval)
            }
        }
    }

    /// The power source changed: the next frame comes `interval` seconds after the last one. The tap, its aggregate
    /// device and the privacy indicator are untouched.
    func retune(interval: Double) {
        let clamped = Self.clamped(interval)
        guard clamped != self.interval else { return }
        self.interval = clamped
        if isRunning { log.info("live visualizer: \(Int((1 / clamped).rounded()), privacy: .public) fps") }
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
        onFrame(LiveFrame(bars: analyzer.barLevels, energy: energy, hasAudio: rms > 1e-5))
    }
}
