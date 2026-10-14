import AppKit
import CrannyCore
import Foundation
import Testing
@testable import CrannyEffects

// The dedicated layer's energy rules (ARCHITECTURE.md §9.2): no frame loop while paused, hidden or occluded; a paused
// layer redraws only when an input changes. The window is never ordered in, so nothing appears on screen and the
// window server reports it as occluded.

@MainActor private func hostedView(_ state: AmbientLayerState) throws -> (AmbientMetalNSView, NSWindow) {
    let renderer = try #require(AmbientRenderer.shared)
    let view = AmbientMetalNSView(renderer: renderer)
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
