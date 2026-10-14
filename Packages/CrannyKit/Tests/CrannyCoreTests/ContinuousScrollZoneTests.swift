import CoreGraphics
import Foundation
import Testing
@testable import CrannyCore

// Continuous (value) scroll zones never commit (`crannyContinuousScrollZone`, `SwipeTracker.continuous`).

private func scrollSample(_ phase: SwipePhase, dy: CGFloat = 0, at t: TimeInterval) -> ScrollSample {
    ScrollSample(phase: phase, isMomentum: false, deltaX: 0, deltaY: dy, isPrecise: true,
                 isInvertedFromDevice: true, timestamp: t)
}

@Test func continuousTrackerTracksTheWholeTouchAndNeverCommits() {
    var t = SwipeTracker.continuous(axis: .vertical)
    _ = t.handle(scrollSample(.began, at: 0))
    var last: SwipeUpdate?
    for i in 1...20 {                                                           // 20 × 10 pt, far past any commit distance
        last = t.handle(scrollSample(.changed, dy: -10, at: Double(i) * 0.016))
        #expect(last == .tracking(.vertical, translation: CGFloat(-10 * i)))
    }
    #expect(t.handle(scrollSample(.ended, at: 0.4)) == .cancelled)               // fast release: still no commit
}

@MainActor @Test func continuousZonesReportTrackingPastTheGestureThresholds() {
    let zones = NotchZones()
    var updates: [SwipeUpdate] = []
    zones.setScrollZone(.init(id: "timer.face", frame: CGRect(x: 0, y: 0, width: 100, height: 100), axis: .vertical,
                              onUpdate: { updates.append($0) }, commits: false))
    let p = CGPoint(x: 50, y: 50)
    #expect(zones.scroll(scrollSample(.began, at: 0), at: p))
    for i in 1...6 { _ = zones.scroll(scrollSample(.changed, dy: -10, at: Double(i) * 0.016), at: p) }
    _ = zones.scroll(scrollSample(.ended, at: 0.2), at: p)
    #expect(updates.count == 7)
    #expect(updates[5] == .tracking(.vertical, translation: -60))               // a gesture zone stops after 18 pt
    #expect(updates.last == .cancelled)
    #expect(!updates.contains { if case .committed = $0 { true } else { false } })
}
