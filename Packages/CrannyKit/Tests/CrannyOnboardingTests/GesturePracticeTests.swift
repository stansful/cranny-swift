import CoreGraphics
import CrannyCore
import Foundation
import Testing
@testable import CrannyOnboarding

/// A two-finger touch sequence: began, `steps` × (dx, dy) of finger travel 1/60 s apart, then ended.
/// "Natural scrolling" deltas follow the fingers (+y = down).
private func touch(dx: CGFloat = 0, dy: CGFloat = 0, steps: Int, start: TimeInterval = 0) -> [ScrollSample] {
    var samples = [ScrollSample(phase: .began, isMomentum: false, deltaX: 0, deltaY: 0, isPrecise: true,
                                isInvertedFromDevice: true, timestamp: start)]
    for i in 1...steps {
        samples.append(ScrollSample(phase: .changed, isMomentum: false, deltaX: dx, deltaY: dy, isPrecise: true,
                                    isInvertedFromDevice: true, timestamp: start + Double(i) / 60))
    }
    samples.append(ScrollSample(phase: .ended, isMomentum: false, deltaX: 0, deltaY: 0, isPrecise: true,
                                isInvertedFromDevice: true, timestamp: start + Double(steps + 1) / 60))
    return samples
}

@Suite struct GesturePracticeTests {
    @Test func pullingDownRubberBandsThenOpens() {
        var practice = GesturePractice(allowsTrackSwipe: false)
        let effects = touch(dy: 10, steps: 3).flatMap { practice.handle($0) }
        guard case .follow(let first)? = effects.first else {
            Issue.record("expected live rubber-banding first, got \(effects)")
            return
        }
        #expect(first.height > 0 && first.height < 10)        // resistance: less than the finger travelled
        #expect(effects.contains(.open))
        #expect(effects.last != .snapBack)
        #expect(practice.isOpen)
    }

    @Test func pushingUpClosesAnOpenPracticeNotch() {
        var practice = GesturePractice(allowsTrackSwipe: false)
        _ = touch(dy: 10, steps: 3).flatMap { practice.handle($0) }
        let effects = touch(dy: -10, steps: 3, start: 1).flatMap { practice.handle($0) }
        #expect(effects.contains(.close))
        #expect(!practice.isOpen)
    }

    @Test func aShortSlowPullSnapsBack() {
        var practice = GesturePractice(allowsTrackSwipe: false)
        let effects = touch(dy: 2.5, steps: 2).flatMap { practice.handle($0) }   // 5 pt at 150 pt/s: below both thresholds
        #expect(effects.last == .snapBack)
        #expect(!practice.isOpen)
    }

    @Test func sidewaysSwipesNeedSomethingPlaying() {
        var silent = GesturePractice(allowsTrackSwipe: false)
        let ignored = touch(dx: 15, steps: 4).flatMap { silent.handle($0) }
        #expect(ignored.allSatisfy { $0 == .snapBack || $0 == .follow(.zero) })

        var playing = GesturePractice(allowsTrackSwipe: true)
        let effects = touch(dx: 15, steps: 4).flatMap { playing.handle($0) }
        #expect(effects.contains(.track(.swipeRight)))
        var inverted = GesturePractice(allowsTrackSwipe: true, invertsTrackSwipe: true)
        let mirrored = touch(dx: 15, steps: 4).flatMap { inverted.handle($0) }
        #expect(mirrored.contains(.track(.swipeLeft)))
    }

    @Test func momentumAndWheelsAreIgnored() {
        var practice = GesturePractice(allowsTrackSwipe: true)
        let wheel = ScrollSample(phase: [], isMomentum: false, deltaX: 0, deltaY: 40, isPrecise: false,
                                 isInvertedFromDevice: true, timestamp: 0)
        let momentum = ScrollSample(phase: .changed, isMomentum: true, deltaX: 0, deltaY: 40, isPrecise: true,
                                    isInvertedFromDevice: true, timestamp: 0)
        let fromWheel = practice.handle(wheel)
        let fromMomentum = practice.handle(momentum)
        #expect(fromWheel.isEmpty)
        #expect(fromMomentum.isEmpty)
    }
}
