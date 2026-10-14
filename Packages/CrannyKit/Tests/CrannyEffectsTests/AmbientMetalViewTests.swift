import AppKit
import CrannyCore
import Foundation
import QuartzCore
import Testing
@testable import CrannyEffects

// The dedicated layer's energy rules (ARCHITECTURE.md §9.2): no frame loop while paused, hidden or occluded; a paused
// layer redraws only when an input changes, once per main-queue turn, and not while occluded; the drawable covers only
// the lit band and does not reallocate on every resize frame. The window is never ordered in, so nothing appears on
// screen and the window server reports it as occluded (tests that need it visible say so: `treatsWindowAsVisible`).

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
    window.contentView = view
    #expect(view.renderer != nil)
    view.stop()
    #expect(view.renderer == nil)
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
