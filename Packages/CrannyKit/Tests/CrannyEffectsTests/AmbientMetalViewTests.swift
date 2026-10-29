import AppKit
import CrannyCore
import Foundation
import QuartzCore
import Testing
@testable import CrannyEffects

// The dedicated layer's energy rules (ARCHITECTURE.md §9.2): no frame loop while paused, hidden or occluded; steady
// frames on the render thread at the budget's rate, time continuing across a pause; a paused layer redraws only when
// an input changes, once per main-queue turn, and not while occluded; the drawable covers only the lit band and does
// not reallocate on every resize frame. The window is never ordered in, so nothing appears on screen and the window
// server reports it as occluded (tests that need it visible say so: `treatsWindowAsVisible`).

@MainActor private func hostedView(_ state: AmbientLayerState) throws -> (AmbientMetalNSView, NSWindow) {
    let view = AmbientMetalNSView()
    view.state = state
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 130), styleMask: .borderless,
                          backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = view
    return (view, window)
}

@Test(.enabled(if: shadersRun)) func pausedLayerDrawsOnlyWhenAnInputChanges() async throws {
    var state = layerState(.aurora)
    state.interval = nil                                                // paused budget
    let (view, window) = try hostedView(state)
    defer { window.close() }
    view.treatsWindowAsVisible = true
    #expect(!view.isRunning)
    let first = view.framesDrawn
    #expect(first >= 1, "a paused layer still shows its frame")
    view.state = state                                                  // nothing changed
    await view.pausedRedraw?.value
    #expect(view.framesDrawn == first)
    state.fill = 0.4                                                    // the drain animates while time stands still
    view.state = state
    state.energy = 0.3                                                  // a second input in the same turn
    view.state = state
    await view.pausedRedraw?.value
    #expect(view.framesDrawn == first + 1, "one frame per turn, however many inputs change")
}

/// An input that changes together with the size (the fill rising during the open morph while paused) costs one frame,
/// the resize frame, not two.
@Test(.enabled(if: shadersRun)) func pausedInputAndResizeInOneTurnDrawOnce() async throws {
    var state = layerState(.motes)
    state.interval = nil
    let (view, window) = try hostedView(state)
    defer { window.close() }
    view.treatsWindowAsVisible = true
    let first = view.framesDrawn
    state.fill = 0.5
    view.state = state                                                  // SwiftUI's update…
    view.setFrameSize(NSSize(width: 440, height: 150))                  // …then its layout, in the same turn
    #expect(view.framesDrawn == first + 1)
    await view.pausedRedraw?.value
    #expect(view.framesDrawn == first + 1, "the resize frame already showed the new fill")
}

/// While the window is occluded a paused layer draws nothing for its inputs; it shows the latest one when revealed.
@Test(.enabled(if: shadersRun)) func occludedPausedLayerRedrawsWhenRevealed() async throws {
    var state = layerState(.tide)
    state.interval = nil
    let (view, window) = try hostedView(state)
    defer { window.close() }
    #expect(!window.occlusionState.contains(.visible))
    let first = view.framesDrawn
    state.fill = 0.6
    view.state = state
    await view.pausedRedraw?.value
    #expect(view.framesDrawn == first, "nobody can see this frame")
    view.treatsWindowAsVisible = true                                   // revealed
    NotificationCenter.default.post(name: NSWindow.didChangeOcclusionStateNotification, object: window)
    #expect(view.framesDrawn == first + 1)
}

@Test(.enabled(if: shadersRun)) func occludedLayerRunsNoLoop() async throws {
    var state = layerState(.tide)
    state.interval = 1.0 / 30
    let (view, window) = try hostedView(state)
    defer { window.close() }
    #expect(!window.occlusionState.contains(.visible))
    #expect(!view.isRunning, "an occluded window must not wake 30 times a second")
    let frames = view.framesDrawn
    try await Task.sleep(for: .milliseconds(200))
    #expect(view.framesDrawn == frames)
}

/// A running layer draws its steady frames on its render thread: they keep coming while the main thread is busy, with
/// the energy read from a shared level; a main-actor energy closure leaves them to the main thread; a stopped layer
/// draws nothing more.
@Test(.enabled(if: shadersRun)) func runningLayerDrawsOffTheMainThread() async throws {
    let level = AudioEnergyLevel()
    level.set(0.5)
    let (view, window) = try await runningView(layerState(.aurora), energy: AmbientEnergySource(level))   // 30 fps
    defer { window.close() }
    var before = view.framesDrawnOffMain
    blockMainThread(for: 0.5)                                           // the main thread is busy for 15 frames
    #expect(view.framesDrawnOffMain - before >= 5, "\(view.framesDrawnOffMain - before) frames off the main thread")
    view.energySource = AmbientEnergySource { 0.5 }                     // energy only on the main actor
    before = view.framesDrawn
    blockMainThread(for: 0.3)
    #expect(view.framesDrawn == before, "these frames wait for the main thread")
    let offMain = view.framesDrawnOffMain
    try await eventually { view.framesDrawn > before + 1 }
    #expect(view.framesDrawn > before + 1, "and the main thread draws them")
    #expect(view.framesDrawnOffMain == offMain)
    view.stop()
    before = view.framesDrawn
    try await Task.sleep(for: .milliseconds(200))
    #expect(view.framesDrawn == before)
}

/// The render thread draws at the budget's rate: 20 fps on battery, at most 30 on AC, never a burst. The rate is
/// counted over the time the main thread was really blocked, which a loaded Mac stretches past the 0.6 s asked for.
@Test(.enabled(if: shadersRun)) func renderThreadKeepsTheBudgetsRate() async throws {
    var state = layerState(.tide)
    state.interval = 1.0 / 20
    let (view, window) = try await runningView(state)
    defer { view.stop(); window.close() }
    let battery = framesOffMain(view, blocking: 0.6)
    #expect(battery.count >= 4 && Double(battery.count) <= battery.seconds * 20 + 1,
            "\(battery.count) frames in \(battery.seconds) s at 20 fps")
    state.interval = 1.0 / 30                                           // plugged in: the same thread, a new rate
    view.state = state
    let mains = framesOffMain(view, blocking: 0.6)
    #expect(mains.count >= 6 && Double(mains.count) <= mains.seconds * 30 + 1,
            "\(mains.count) frames in \(mains.seconds) s at 30 fps")
}

/// Time continues across a pause (Reduce Motion, occlusion, a paused budget): the first frame after it shows the last
/// frame's time, not the wall clock, and the render thread goes on from there.
@Test(.enabled(if: shadersRun)) func renderThreadContinuesTimeAcrossAPause() async throws {
    var state = layerState(.motes)
    let (view, window) = try await runningView(state)
    defer { view.stop(); window.close() }
    state.interval = nil                                                // paused: no more frames off the main thread
    view.state = state
    await view.pausedRedraw?.value
    let paused = try #require(view.lastFrameTime)
    let offMain = view.framesDrawnOffMain
    try await Task.sleep(for: .milliseconds(300))
    #expect(view.framesDrawnOffMain == offMain)
    #expect(view.lastFrameTime == paused, "a paused layer keeps its time")
    state.interval = 1.0 / 30                                           // resumed
    let resumedAt = ContinuousClock.now
    view.state = state
    let resumed = shaderSeconds(from: paused, to: try #require(view.lastFrameTime))
    #expect(resumed < 0.05, "resumed \(resumed) s after the pause's time")
    blockMainThread(for: 0.3)
    #expect(view.framesDrawnOffMain > offMain)
    let later = shaderSeconds(from: paused, to: try #require(view.lastFrameTime))
    let running = (ContinuousClock.now - resumedAt) / .seconds(1)      // 0.3 s, or more on a loaded Mac
    #expect(later > 0.15 && later < running + 0.1, "\(later) s after \(running) s of frames")
}

/// Shader seconds from `start` to `end` (the shader clock wraps every hour).
private func shaderSeconds(from start: Double, to end: Double) -> Double {
    (end - start + 3600).truncatingRemainder(dividingBy: 3600)
}

/// While the loop runs, a resize is drawn on the main thread inside the transaction, and so are the frame that returns
/// the grown drawable to the band and the one after it (each changes the layer); then the render thread draws again.
@Test(.enabled(if: shadersRun)) func runningLayerLeavesLayerChangesToTheMainThread() async throws {
    let (view, window) = try await runningView(layerState(.motes))
    defer { view.stop(); window.close() }
    for step in 1...10 { view.setFrameSize(NSSize(width: 440 + Double(step) * 3.3, height: 130 + Double(step) * 1.7)) }
    view.setFrameSize(NSSize(width: 450, height: 140))                  // shrinking: the drawable keeps its slack
    #expect(view.drawableLayout?.hasSlack == true)
    #expect(view.metalLayer.presentsWithTransaction)
    let offMain = view.framesDrawnOffMain
    blockMainThread(for: 0.3)                                           // ticks come, none may draw off the main thread
    #expect(view.framesDrawnOffMain == offMain)
    try await eventually { view.framesDrawnOffMain > offMain }
    #expect(view.drawableLayout?.hasSlack == false, "the main thread returned the drawable to the band")
    #expect(!view.metalLayer.presentsWithTransaction)
}

/// The main thread changes everything a frame depends on while the render thread draws as fast as it may (240 fps):
/// sizes, effects, inputs, energy sources, the window, occlusion, the rate, then a stop in the middle of it. Every
/// frame still draws one consistent snapshot (Thread Sanitizer runs of this test find no race), and the render thread
/// goes on drawing whenever nothing changes the layer.
@Test(.enabled(if: shadersRun)) func renderThreadSurvivesMainThreadChurn() async throws {
    let level = AudioEnergyLevel()
    var state = layerState(.aurora)
    state.interval = 1.0 / 240
    let (view, window) = try await runningView(state, energy: AmbientEnergySource(level))
    defer { window.close() }
    let effects: [AmbientEffect] = [.motes, .tide, .halo, .aurora]
    for step in 0..<48 {
        level.set(Double(step % 10) / 10)
        switch step % 8 {
        case 0: view.setFrameSize(NSSize(width: 400 + Double(step), height: 120 + Double(step % 5)))
        case 1: state.effect = effects[step / 8 % effects.count]; view.state = state
        case 2: state.fill = Double(step % 7) / 6; view.state = state
        case 3: view.energySource = step % 16 == 3 ? AmbientEnergySource { 0.2 } : AmbientEnergySource(level)
        case 4: window.contentView = nil; window.contentView = view
        case 5:
            view.treatsWindowAsVisible.toggle()
            NotificationCenter.default.post(name: NSWindow.didChangeOcclusionStateNotification, object: window)
        case 6: state.interval = step % 16 == 6 ? 1.0 / 120 : 1.0 / 240; view.state = state
        default: view.treatsWindowAsVisible = true
            NotificationCenter.default.post(name: NSWindow.didChangeOcclusionStateNotification, object: window)
        }
        try await Task.sleep(for: .milliseconds(6))
    }
    view.energySource = AmbientEnergySource(level)
    let offMain = view.framesDrawnOffMain
    try await eventually { view.framesDrawnOffMain > offMain + 2 }
    #expect(view.framesDrawnOffMain > offMain + 2, "the render thread draws again once the layer is left alone")
    view.stop()                                                         // while it draws
    let frames = view.framesDrawn
    try await Task.sleep(for: .milliseconds(50))
    #expect(view.framesDrawn == frames)
}

/// The render thread holds its loop only until `stop()`: then it removes its timer, ends and lets the loop go.
@Test func stoppedLoopEndsItsThread() async throws {
    weak var weakLoop: AmbientFrameLoop?
    do {
        let loop = AmbientFrameLoop(layer: CAMetalLayer())
        weakLoop = loop
        loop.run(at: 1.0 / 30)
        try await Task.sleep(for: .milliseconds(100))                   // the thread is up and ticking
        loop.run(at: nil)
        loop.run(at: 1.0 / 20)
        loop.stop()
    }
    try await eventually { weakLoop == nil }
    #expect(weakLoop == nil, "the thread ended and let its loop go")
}

/// A view whose loop runs and has drawn on its render thread. The window is never ordered in; `treatsWindowAsVisible`
/// stands for a visible one.
@MainActor private func runningView(_ state: AmbientLayerState, energy: AmbientEnergySource? = nil) async throws
    -> (AmbientMetalNSView, NSWindow) {
    let (view, window) = try hostedView(state)
    view.energySource = energy
    view.treatsWindowAsVisible = true
    NotificationCenter.default.post(name: NSWindow.didChangeOcclusionStateNotification, object: window)
    #expect(view.isRunning)
    try await eventually { view.framesDrawnOffMain > 0 }
    try #require(view.framesDrawnOffMain > 0, "the render thread draws")
    return (view, window)
}

/// Waits until `condition` holds, checking every 20 ms for at most `turns` checks. Bounded by main-actor turns, not by
/// the clock: parallel suites can keep the main actor busy for more than ten seconds, and the frames these tests wait
/// for need main-actor turns too.
@MainActor private func eventually(turns: Int = 500, _ condition: () -> Bool) async throws {
    for _ in 0..<turns where !condition() { try await Task.sleep(for: .milliseconds(20)) }
}

/// Keeps the main thread from running anything else for `seconds`.
@MainActor private func blockMainThread(for seconds: Double) { Thread.sleep(forTimeInterval: seconds) }

/// The frames `view` draws off the main thread while it is blocked for `seconds`, and how long it really was blocked: a
/// loaded Mac (CI's three-core virtual machine) wakes the sleep late, and the render thread draws on meanwhile.
@MainActor private func framesOffMain(_ view: AmbientMetalNSView, blocking seconds: Double)
    -> (count: Int, seconds: Double) {
    let start = ContinuousClock.now
    let before = view.framesDrawnOffMain
    blockMainThread(for: seconds)
    let count = view.framesDrawnOffMain - before
    return (count, (ContinuousClock.now - start) / .seconds(1))
}

@Test(.enabled(if: shadersRun)) func dismantledLayerStops() throws {
    var state = layerState(.motes)
    state.interval = nil
    let (view, window) = try hostedView(state)
    defer { window.close() }
    view.stop()
    #expect(!view.isRunning)
    #expect(view.hitTest(NSPoint(x: 10, y: 10)) == nil, "light never takes a click")
}

/// The view holds a renderer only while it is in a window, and lets it go when it leaves or is dismantled.
@Test(.enabled(if: shadersRun)) func layerHoldsItsRendererOnlyInAWindow() throws {
    var state = layerState(.aurora)
    state.interval = nil
    let view = AmbientMetalNSView()
    view.state = state
    #expect(view.renderer == nil)
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 130), styleMask: .borderless,
                          backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    defer { window.close() }
    window.contentView = view
    #expect(view.renderer != nil)
    window.contentView = nil
    #expect(view.renderer == nil, "a view out of its window must not keep the GPU")
    #expect(view.metalLayer.device == nil, "nor may its layer")
    #expect(!view.renderThreadHasInputs, "nor its render thread")
    window.contentView = view
    #expect(view.renderer != nil)
    #expect(view.renderThreadHasInputs)
    view.stop()
    #expect(view.renderer == nil)
    #expect(!view.renderThreadHasInputs)
}

/// A resize (the open and close morph) draws exactly one frame at the new size, presented with the new bounds; a
/// layout pass that keeps the size draws nothing. Paced like a 120-Hz morph (one layout per display frame); in
/// integration runs the median main-thread cost per resize must stay far below the 8.3-ms frame.
@Test(.enabled(if: shadersRun)) func resizeDrawsOneSynchronizedFrame() throws {
    var state = layerState(.aurora)
    state.interval = nil                                                // paused: only resizes and inputs draw
    let (view, window) = try hostedView(state)
    defer { window.close() }
    let start = view.framesDrawn
    view.setFrameSize(NSSize(width: 440, height: 160))
    #expect(view.framesDrawn == start + 1)
    view.setFrameSize(NSSize(width: 440, height: 160))
    #expect(view.framesDrawn == start + 1, "same size: nothing to draw")
    let clock = ContinuousClock()
    var times: [Duration] = []
    for step in 1...60 {
        times.append(clock.measure { view.setFrameSize(NSSize(width: 440, height: 160 + Double(step) * 2)) })
        RunLoop.main.run(until: Date().addingTimeInterval(1.0 / 120))   // Core Animation commits between layouts
    }
    #expect(view.framesDrawn == start + 61)
    if integrationTests {                                               // hardware-dependent (ARCHITECTURE.md §9.6)
        let median = times.sorted()[times.count / 2]
        #expect(median < .milliseconds(2), "\(median) of main-thread time per resize")
    }
}

/// The drawable covers only the lit band (aurora: below 40 % of the height, less the ripple's reach), at the bottom of
/// the view, one pixel per device pixel; the rows above it are never drawn.
@Test(.enabled(if: shadersRun)) func drawableCoversOnlyTheLitBand() throws {
    var state = layerState(.aurora)
    state.interval = nil
    let (view, window) = try hostedView(state)
    defer { window.close() }
    let layout = try #require(view.drawableLayout)
    let scale = AmbientRenderer.renderScale(for: .aurora, displayScale: window.backingScaleFactor)
    let top = AmbientRenderer.litTop(.aurora, height: 130, energy: 0)
    #expect(top == (0.40 * 130 - 7).rounded(.down))
    #expect(layout.offset == Int(top * scale))
    #expect(view.metalLayer.drawableSize == CGSize(width: 440 * scale, height: 130 * scale - CGFloat(layout.offset)))
    let frame = try #require(view.subviews.first).frame
    #expect(frame == CGRect(x: 0, y: 0, width: 440, height: 130 - top), "the band sits at the bottom of the view")
    #expect(!layout.hasSlack)
}

/// During a morph the drawable grows in 64-pixel steps instead of changing size on every frame, never shrinks while
/// resizing, and returns to the band's exact size with the next frame drawn at rest.
@Test(.enabled(if: shadersRun)) func resizingDrawableGrowsInStepsAndSettles() async throws {
    var state = layerState(.motes)
    state.interval = nil
    let (view, window) = try hostedView(state)
    defer { window.close() }
    view.treatsWindowAsVisible = true
    var reallocations = 0
    for step in 1...40 {
        let before = view.metalLayer.drawableSize
        view.setFrameSize(NSSize(width: 440 + Double(step) * 3.3, height: 130 + Double(step) * 1.7))
        if view.metalLayer.drawableSize != before { reallocations += 1 }
    }
    #expect(reallocations <= 6, "\(reallocations) new drawable sizes over 40 resize frames")
    let grown = view.metalLayer.drawableSize
    view.setFrameSize(NSSize(width: 450, height: 140))                  // shrinking: the drawable is kept
    #expect(view.metalLayer.drawableSize == grown)
    let layout = try #require(view.drawableLayout)
    #expect(layout.hasSlack && layout.pixels == grown)
    state.fill = 0.7                                                    // the next frame at rest
    view.state = state
    await view.pausedRedraw?.value
    let settled = try #require(view.drawableLayout)
    #expect(!settled.hasSlack)
    #expect(view.metalLayer.drawableSize == settled.region)
    let scale = AmbientRenderer.renderScale(for: .motes, displayScale: window.backingScaleFactor)
    #expect(settled.region.width == 450 * scale)
}
