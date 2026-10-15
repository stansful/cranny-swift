import AppKit
import CrannyCore
import Foundation
import Testing
@testable import CrannyEffects

// Live audio energy reaches the Metal layer as a source it samples once per frame drawn (AmbientEnergySource.swift),
// never as a SwiftUI input: a change of the energy alone draws nothing, and each frame reads the energy of its moment.

@Test func energySamplesAreClampedToTheUnitRange() {
    #expect(AmbientEnergySource { 1.7 }.sample() == 1)
    #expect(AmbientEnergySource { -0.2 }.sample() == 0)
    #expect(AmbientEnergySource { 0.4 }.sample() == 0.4)
}

/// A shared level reads the same values, and on any thread: the Metal layer's render thread reads it there.
@Test func levelSourceIsReadableOffTheMainActor() async {
    let level = AudioEnergyLevel()
    level.set(1.4)
    let source = AmbientEnergySource(level)
    #expect(source.sample() == 1)
    #expect(source.level === level)
    #expect(AmbientEnergySource { 0.4 }.level == nil, "a closure is read on the main actor only")
    level.set(0.3)
    let offMain = await Task.detached { AmbientEnergySource.clamped(level.current) }.value
    #expect(offMain == 0.3)
}

/// The music's loudness as the source reads it, counting the reads.
private final class Loudness {
    var level = 0.2
    var reads = 0
    var source: AmbientEnergySource { AmbientEnergySource { self.reads += 1; return self.level } }
}

@Test(.enabled(if: shadersRun)) @MainActor func layerSamplesTheEnergyOncePerFrameItDraws() async throws {
    var state = layerState(.aurora)
    state.interval = nil                                                // paused: frames only on input changes
    let view = AmbientMetalNSView()
    let loudness = Loudness()
    view.energySource = loudness.source
    view.state = state
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 130), styleMask: .borderless,
                          backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = view
    defer { window.close() }
    view.treatsWindowAsVisible = true
    let frames = view.framesDrawn
    #expect(frames >= 1 && loudness.reads == frames, "every frame drawn so far read the energy once")
    loudness.level = 0.9                                                // the music got louder: nothing to draw yet
    view.energySource = loudness.source                                 // a SwiftUI update hands over a new source
    await view.pausedRedraw?.value
    #expect(view.framesDrawn == frames && loudness.reads == frames)
    state.fill = 0.5                                                    // an input change draws one frame
    view.state = state
    await view.pausedRedraw?.value
    #expect(view.framesDrawn == frames + 1 && loudness.reads == frames + 1)
}
