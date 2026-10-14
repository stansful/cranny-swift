import CoreGraphics
import Foundation
import Testing
@testable import CrannyCore

// Additive Core change requested by WP1: a value zone with `onEnd:` tells a release from a system cancel
// (Additions/WP01-ScrollEnd.swift). Zones without it keep the `.cancelled` update.

private func sample(_ phase: SwipePhase, dx: CGFloat = 0, at t: TimeInterval) -> ScrollSample {
    ScrollSample(phase: phase, isMomentum: false, deltaX: dx, deltaY: 0, isPrecise: true,
                 isInvertedFromDevice: true, timestamp: t)
}

@Test func scrollEndFollowsThePhase() {
    #expect(NotchZones.ScrollEnd(.ended) == .released)
    #expect(NotchZones.ScrollEnd(.cancelled) == .cancelled)
    #expect(NotchZones.ScrollEnd([.ended, .cancelled]) == .cancelled)
    #expect(NotchZones.ScrollEnd(.changed) == nil)
    #expect(NotchZones.ScrollEnd(.began) == nil)
    #expect(NotchZones.ScrollEnd([]) == nil)
}

@MainActor private final class Recorder {
    var updates: [SwipeUpdate] = []
    var ends: [NotchZones.ScrollEnd] = []
}

/// A 180-pt scrubber-like zone; one touch of `steps` × 10 pt to the right, ended with `last`.
@MainActor private func scroll(steps: Int, endingWith last: SwipePhase, onEnd: Bool = true) -> Recorder {
    let zones = NotchZones(), recorder = Recorder()
    var end: (@MainActor (NotchZones.ScrollEnd) -> Void)?
    if onEnd { end = { recorder.ends.append($0) } }
    zones.setScrollZone(.init(id: "media.seek", frame: CGRect(x: 0, y: 0, width: 180, height: 24), axis: .horizontal,
                              onUpdate: { recorder.updates.append($0) }, commits: false, onEnd: end))
    let p = CGPoint(x: 90, y: 12)
    _ = zones.scroll(sample(.began, at: 0), at: p)
    for i in 0..<steps { _ = zones.scroll(sample(.changed, dx: 10, at: Double(i + 1) * 0.016), at: p) }
    _ = zones.scroll(sample(last, at: Double(steps + 1) * 0.016), at: p)
    return recorder
}

@MainActor @Test func valueZoneReportsARelease() {
    let r = scroll(steps: 12, endingWith: .ended)                        // 120 pt: far past any commit distance
    #expect(r.updates.count == 12)
    #expect(r.updates.last == .tracking(.horizontal, translation: 120))
    #expect(r.ends == [.released])
    #expect(!r.updates.contains(.cancelled))
}

@MainActor @Test func valueZoneReportsASystemCancel() {
    let r = scroll(steps: 3, endingWith: .cancelled)
    #expect(r.updates.last == .tracking(.horizontal, translation: 30))
    #expect(r.ends == [.cancelled])
    #expect(!r.updates.contains(.cancelled))
}

@MainActor @Test func zonesWithoutOnEndAreUnchanged() {
    #expect(scroll(steps: 3, endingWith: .cancelled, onEnd: false).updates.last == .cancelled)
    #expect(scroll(steps: 3, endingWith: .ended, onEnd: false).updates.last == .cancelled)
}

@MainActor @Test func aTouchThatNeverMovedReportsNoEnd() {
    // Fingers that touched and were cancelled without moving never locked to an axis: nothing to apply or discard.
    let r = scroll(steps: 0, endingWith: .cancelled)
    #expect(r.updates.isEmpty)
    #expect(r.ends.isEmpty)
}
