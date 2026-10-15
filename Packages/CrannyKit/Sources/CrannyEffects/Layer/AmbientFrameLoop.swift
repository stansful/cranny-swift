// CrannyEffects/Layer/AmbientFrameLoop.swift — the ambient Metal layer's steady frames, drawn on a render thread of
// their own (ARCHITECTURE.md §9.2).
//
// Why: the main thread spent about 3 ms per second drawing the light, but every frame woke three threads besides
// the GPU's queues: a dispatch timer on a cooperative thread (`Task.sleep`), the hop to the main actor, and a pass of
// the main run loop's observers (AppKit, SwiftUI, Core Animation). Now a steady frame wakes one thread, which draws.
//
// How: `AmbientMetalNSView` owns one loop. While the budget runs, the loop's thread serves a repeating
// `CFRunLoopTimer` on its own run loop at the budget's interval (30 fps on AC, 20 on battery) with an eighth of an
// interval of tolerance: the pacing of the main-actor loop it replaces, whatever the display's refresh rate. The
// timer is removed whenever the view says the loop must not run (budget paused, window occluded or gone, no size,
// hidden), and the thread then waits without a wakeup. The view publishes what a frame needs (`Inputs`: state, size,
// scale, drawable layout, renderer, energy level) whenever one of them changes; the thread draws from that snapshot
// and reads the live energy itself (`AudioEnergyLevel`), with no hop to the main actor.
//
// The main thread keeps: resize frames (presented inside the Core Animation transaction), the frame that returns a
// grown drawable to the band and the one after it (each changes the layer), paused redraws, the first frame of a
// starting loop, and every steady frame while the energy comes from a main-actor closure. A tick that needs the main
// thread asks for one frame there (once, however many ticks ask). One lock serializes every draw and holds the books
// (time, last frame, frames drawn): one frame at a time, a tick within half an interval of the last frame draws
// nothing (a resize already draws each display frame), and time continues across a pause exactly as before. The
// layer's and the drawable view's properties change only on the main thread and only under that lock, so the render
// thread never draws into a drawable whose size or place is changing.
//
// Lifetime: the thread starts with the first loop that runs and ends on `stop()` (dismantle, or the view's deinit);
// it holds the loop until then, never the view.
import CrannyCore
import Foundation
import QuartzCore
import os

nonisolated final class AmbientFrameLoop: @unchecked Sendable {
    // @unchecked: `Shared` sits behind `lock`; `layer` is drawn into only under it (its properties change only on the
    // main thread, under it too); `onMainFrame` is main-actor state; a `Worker`'s fields are argued at its type.

    /// What a steady frame needs. The view publishes a new value whenever one of these changes.
    nonisolated struct Inputs: Sendable {
        var state: AmbientLayerState
        /// The view's bounds in points, and pixels per point of the drawable.
        var size: CGSize
        var scale: CGFloat
        var layout: AmbientDrawableLayout
        var renderer: AmbientRenderer
        /// The live energy, read in each frame (nil: `state.energy`).
        var energy: AudioEnergyLevel?
        /// Whether the render thread may draw the next steady frame. False while the energy comes from a main-actor
        /// closure, and while the next frame changes the layer: the drawable has slack or a new frame or size, or the
        /// layer still presents with the transaction (a synchronized frame was the last).
        var drawsOffMain: Bool
    }

    /// Everything both threads touch.
    nonisolated struct Shared: Sendable {
        var inputs: Inputs?
        /// The running loop's frame interval; nil while paused.
        var interval: Double?
        /// Shader time of the last frame drawn, and the offset that makes a resumed loop continue from it.
        var lastTime: Double?
        var timeOffset: Double = 0
        /// When the last frame was drawn: a tick right after a resize frame is skipped (one draw per frame at most).
        var lastDrawn: ContinuousClock.Instant?
        /// Frames drawn, and those of them the render thread drew (tests and diagnostics).
        var framesDrawn = 0
        var framesDrawnOffMain = 0
        /// An input changed after the last frame drawn (any frame shows the latest state).
        var hasUndrawnInput = false
        /// A tick asked the main thread for a frame, which has not drawn it yet.
        var mainFrameRequested = false
        /// The render thread now, nil until a loop first runs and after `stop()`.
        var worker: Worker?
    }

    /// One render thread. `runLoop` and `ends` are guarded by the loop's lock; `timer` and `timerInterval` belong to
    /// the thread (the timer is added to, replaced on and invalidated on that thread's run loop).
    nonisolated final class Worker: @unchecked Sendable {
        var runLoop: CFRunLoop?
        var ends = false
        var timer: CFRunLoopTimer?
        var timerInterval: Double?
    }

    let layer: CAMetalLayer
    private let lock = OSAllocatedUnfairLock(initialState: Shared())
    /// Draws a loop frame on the main thread (`Inputs.drawsOffMain` false); set by the view.
    @MainActor var onMainFrame: (() -> Void)?

    init(layer: CAMetalLayer) { self.layer = layer }

    /// `body` under the lock: the main thread's draws, layout changes and input updates.
    func withShared<R>(_ body: (inout Shared) throws -> R) rethrows -> R { try lock.withLockUnchecked(body) }

    /// Runs the loop at `interval` seconds per frame, or pauses it (nil). A loop that starts or changes its rate
    /// continues from the last frame's time instead of jumping to the wall clock; its first tick comes one interval
    /// later (the caller draws the first frame).
    func run(at interval: Double?) {
        let (worker, starts) = lock.withLockUnchecked { s -> (Worker?, Bool) in
            s.interval = interval
            guard interval != nil else { return (s.worker, false) }
            if let lastTime = s.lastTime { s.timeOffset = lastTime - EffectTiming.ambientTime(Date()) }
            guard s.worker == nil else { return (s.worker, false) }
            let worker = Worker()
            s.worker = worker
            return (worker, true)
        }
        guard let worker else { return }
        if starts {
            let thread = Thread { [self] in serve(worker) }
            thread.name = "Cranny ambient light"
            thread.qualityOfService = .userInteractive
            thread.start()
        } else {
            signal(worker)
        }
    }

    /// Pauses the loop for good: the thread removes its timer and ends. A later `run` starts a new thread.
    func stop() {
        let worker = lock.withLockUnchecked { s -> Worker? in
            s.interval = nil
            s.mainFrameRequested = false
            let worker = s.worker
            s.worker = nil
            worker?.ends = true
            return worker
        }
        if let worker { signal(worker) }
    }

    /// Draws one frame of `inputs` into `layer` and keeps the books; the caller holds the lock. `energy`: the sample
    /// for this frame (nil: `inputs.state.energy`). `running`: the loop's time (now plus the offset); otherwise the
    /// last frame's time, so a paused layer shows a new input at the same moment.
    @discardableResult
    static func draw(_ s: inout Shared, _ inputs: Inputs, energy: Double?, layer: CAMetalLayer, at date: Date,
                     running: Bool, synchronized: Bool) -> Bool {
        var state = inputs.state
        if let energy { state.energy = energy }
        let time: Double
        if running || s.lastTime == nil {
            let t = (EffectTiming.ambientTime(date) + s.timeOffset).truncatingRemainder(dividingBy: 3600)
            time = t < 0 ? t + 3600 : t
        } else {
            time = s.lastTime ?? state.restingTime
        }
        s.lastTime = time
        let layout = inputs.layout
        let uniforms = AmbientUniforms(state: state, size: inputs.size, scale: inputs.scale, time: time, date: date,
                                       rowOffset: layout.offset)
        guard inputs.renderer.draw(state.effect, uniforms: uniforms, in: layer,
                                   region: layout.hasSlack ? layout.region : nil, synchronized: synchronized)
        else { return false }
        s.hasUndrawnInput = false
        s.framesDrawn += 1
        s.lastDrawn = .now
        return true
    }

    // MARK: - The render thread

    /// The thread's body: a run loop that the timer ticks, kept waiting by a port while there is no timer. On the way
    /// out it drops its timer and its run loop, so a block still queued there (a late `signal`) holds nothing.
    private func serve(_ worker: Worker) {
        let keepAlive = Port()
        RunLoop.current.add(keepAlive, forMode: .default)
        lock.withLockUnchecked { _ in worker.runLoop = CFRunLoopGetCurrent() }
        apply(worker)
        while !lock.withLockUnchecked({ _ in worker.ends }) {
            _ = CFRunLoopRunInMode(.defaultMode, 1e10, false)
        }
        if let timer = worker.timer { CFRunLoopTimerInvalidate(timer) }
        worker.timer = nil
        lock.withLockUnchecked { _ in worker.runLoop = nil }
        keepAlive.invalidate()
    }

    /// Asks `worker`'s thread to apply the loop's state; a thread that has not started yet applies it when it starts,
    /// and one that has ended needs nothing.
    private func signal(_ worker: Worker) {
        lock.withLockUnchecked { _ in
            guard let runLoop = worker.runLoop else { return }
            CFRunLoopPerformBlock(runLoop, CFRunLoopMode.defaultMode.rawValue) { [self] in apply(worker) }
            CFRunLoopWakeUp(runLoop)
        }
    }

    /// On `worker`'s thread: follows the interval (a new timer for a new rate, none while paused) or ends.
    private func apply(_ worker: Worker) {
        let (interval, ends) = lock.withLockUnchecked { s in (s.worker === worker ? s.interval : nil, worker.ends) }
        if interval != worker.timerInterval {
            if let timer = worker.timer { CFRunLoopTimerInvalidate(timer) }
            worker.timer = nil
            worker.timerInterval = interval
            if let interval {
                let timer = CFRunLoopTimerCreateWithHandler(
                    kCFAllocatorDefault, CFAbsoluteTimeGetCurrent() + interval, interval, 0, 0
                ) { [weak self] _ in self?.tick() }
                CFRunLoopTimerSetTolerance(timer, interval / 8)
                CFRunLoopAddTimer(CFRunLoopGetCurrent(), timer, .defaultMode)
                worker.timer = timer
            }
        }
        if ends { CFRunLoopStop(CFRunLoopGetCurrent()) }
    }

    /// One timer tick: draws the steady frame here, or asks the main thread for it.
    private func tick() {
        let needsMain = autoreleasepool {
            lock.withLockUnchecked { s -> Bool in
                guard let interval = s.interval, let inputs = s.inputs else { return false }
                // During a resize the layout already draws every display frame; the loop adds nothing then.
                if let last = s.lastDrawn, ContinuousClock.now - last < .seconds(interval / 2) { return false }
                guard inputs.drawsOffMain else {
                    let asks = !s.mainFrameRequested
                    s.mainFrameRequested = true
                    return asks
                }
                let energy = inputs.energy.map { AmbientEnergySource.clamped($0.current) }
                if Self.draw(&s, inputs, energy: energy, layer: layer, at: Date(), running: true, synchronized: false) {
                    s.framesDrawnOffMain += 1
                }
                return false
            }
        }
        guard needsMain else { return }
        Task { @MainActor [self] in onMainFrame?() }
    }
}
