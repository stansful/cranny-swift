// CrannyMedia/Visualizer/LiveSpectrum.swift — drives the Live visualizer while it is allowed to run: the audio
// tap feeds the ring, a main-actor loop analyzes the latest 1024 samples at the interval the engine asks for (the
// visualizer's frame rate, ≤ 30 fps and ≤ 20 on battery; a 4-Hz probe while nothing it computes is shown) and hands
// 5 bar levels + the smoothed energy to the engine. One sleep per frame to a deadline (no Timer, no TimelineView);
// the loop reads its interval every frame, so `retune` takes effect at the next frame without touching the tap, and
// at once when the interval gets shorter (the loop restarts: bars resume within one frame of a probe).
// The tap starts and stops on one serial queue, in call order, never on the main thread: creating a process tap and
// its aggregate device makes coreaudiod build and publish a device (tens of ms), often while a panel opens. The loop
// starts once the queue reports a running tap, and stops with it.
import CrannyCore
import Foundation
import os

private nonisolated let log = Log.logger(.media)

@available(macOS 14.2, *)
@MainActor final class LiveSpectrum: LiveLevelSource {
    private let tap = SystemAudioTap()
    /// Every `SystemAudioTap.start`/`stop`, in call order (the tap is confined to it).
    private let tapQueue = DispatchQueue(label: "app.cranny.media.live-tap", qos: .userInitiated)
    private let analyzer = SpectrumAnalyzer()
    private var follower = EnergyFollower()
    private var samples = [Float](repeating: 0, count: 1024)
    private var loop: Task<Void, Never>?
    /// A start the tap queue has not answered yet.
    private var isStarting = false
    /// Counts starts and stops: the queue's answer to a start that was stopped meanwhile starts no loop.
    private var generation = 0
    /// Seconds per frame; read by the loop before every frame.
    private(set) var interval: Double = 1.0 / 30
    private let onFrame: @MainActor (LiveFrame) -> Void

    init(onFrame: @escaping @MainActor (LiveFrame) -> Void) { self.onFrame = onFrame }

    var isRunning: Bool { isStarting || loop != nil }

    /// Never faster than 60 fps, whatever the caller asks for.
    nonisolated static func clamped(_ interval: Double) -> Double {
        interval.isFinite ? max(interval, 1.0 / 60) : 1.0 / 30
    }

    /// Starts the tap (prompting the first time) on the tap queue, then the analysis loop at `interval` seconds per
    /// frame. Whether the tap started is reported to `onStart` on the main actor: always for a failure (also when
    /// `stop` overtook the start, unless a newer start is on its way), for a success only if no `stop` came first.
    /// Already running: retunes.
    func start(interval: Double, onStart: @escaping @MainActor (Result<Void, SystemAudioTapError>) -> Void) {
        guard !isRunning else { retune(interval: interval); return }
        self.interval = Self.clamped(interval)
        isStarting = true
        generation += 1
        let generation = generation
        tapQueue.async { [tap] in
            let result = Result<Void, SystemAudioTapError> { () throws(SystemAudioTapError) in try tap.start() }
            Task { @MainActor in self.tapStarted(result, generation: generation, report: onStart) }
        }
    }

    /// The power source changed, or the engine switches between frames and the probe: the next frame comes
    /// `interval` seconds after the last one, or `interval` from now when that is sooner. The tap, its aggregate
    /// device and the privacy indicator are untouched.
    func retune(interval: Double) {
        let clamped = Self.clamped(interval)
        guard clamped != self.interval else { return }
        let sooner = clamped < self.interval
        self.interval = clamped
        guard let loop else { return }                          // starting: the loop begins at the new interval
        if sooner { loop.cancel(); self.loop = makeLoop() }
        log.info("live visualizer: \(Int((1 / clamped).rounded()), privacy: .public) fps")
    }

    func stop() {
        guard isRunning else { return }                         // nothing to tear down: no hop to the tap queue
        generation += 1
        isStarting = false
        loop?.cancel()
        loop = nil
        follower = EnergyFollower()
        tapQueue.async { [tap] in
            if tap.isRunning { log.info("live visualizer: tap stopped") }
            tap.stop()
        }
    }

    /// The tap queue's answer to start number `generation`.
    private func tapStarted(_ result: Result<Void, SystemAudioTapError>, generation: Int,
                            report: @MainActor (Result<Void, SystemAudioTapError>) -> Void) {
        guard generation == self.generation, isStarting else {
            // Stopped meanwhile: `stop` queued the teardown. A failure is still reported (the status, the retry
            // back-off and the permission record), as the start reported it before any stop when it ran on the main
            // thread; not when a newer start is on its way, whose own answer reports.
            if case .failure = result, !isRunning { report(result) }
            return
        }
        isStarting = false
        if case .success = result {
            log.info("live visualizer: tap running")
            loop = makeLoop()
        }
        report(result)
    }

    private func makeLoop() -> Task<Void, Never> {
        Task { [weak self] in
            let clock = ContinuousClock()
            var deadline = clock.now
            while !Task.isCancelled, let interval = self?.interval {
                let next = deadline.advanced(by: .seconds(interval))
                deadline = next > clock.now ? next : clock.now.advanced(by: .seconds(interval))
                do { try await Task.sleep(until: deadline, tolerance: .seconds(interval / 8), clock: clock) } catch { return }
                guard !Task.isCancelled else { return }        // replaced by a retune while this frame was due
                self?.tick(dt: interval)
            }
        }
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
