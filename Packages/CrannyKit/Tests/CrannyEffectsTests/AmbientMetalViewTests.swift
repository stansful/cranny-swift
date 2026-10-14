import AppKit
import CrannyCore
import Foundation
import Testing
@testable import CrannyEffects

// The dedicated layer's energy rules (ARCHITECTURE.md §9.2): no frame loop while paused, hidden or occluded; a paused
// layer redraws only when an input changes. The window is never ordered in, so nothing appears on screen and the
// window server reports it as occluded.

@MainActor private func hostedView(_ state: AmbientLayerState) throws -> (AmbientMetalNSView, NSWindow) {
    let view = AmbientMetalNSView()
    view.state = state
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 130), styleMask: .borderless,
                          backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = view
    return (view, window)
}

@Test(.enabled(if: shadersRun)) func pausedLayerDrawsOnlyWhenAnInputChanges() throws {
    var state = layerState(.aurora)
    state.interval = nil                                                // paused budget
    let (view, window) = try hostedView(state)
    defer { window.close() }
    #expect(!view.isRunning)
    let first = view.framesDrawn
    #expect(first >= 1, "a paused layer still shows its frame")
    view.state = state                                                  // nothing changed
    #expect(view.framesDrawn == first)
    state.fill = 0.4                                                    // the drain animates while time stands still
    view.state = state
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
