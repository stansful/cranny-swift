import CoreGraphics
import CrannyCore
import Foundation
import Testing
@testable import CrannyTodos

/// The "To-do done" moment (DESIGN.md §5.5): who gets which check, and the stateless motes.
struct TodoDelightTests {
    @Test(arguments: [(MotionPersonality.standard, TodoCheckStyle.draw), (.lively, .drawWithMotes),
                      (.calm, .instant), (.instant, .instant)])
    func personalityPicksTheCheck(personality: MotionPersonality, expected: TodoCheckStyle) {
        #expect(TodoCheckStyle.resolve(personality: personality, reduceMotion: false,
                                       isFullScreenInFront: false, areActivitiesPaused: false) == expected)
    }

    @Test func capsGiveTheInstantCheck() {
        for (reduceMotion, fullScreen, paused) in [(true, false, false), (false, true, false), (false, false, true)] {
            #expect(TodoCheckStyle.resolve(personality: .lively, reduceMotion: reduceMotion,
                                           isFullScreenInFront: fullScreen, areActivitiesPaused: paused) == .instant)
        }
    }

    @Test func onlyTheInstantCheckSkipsAnimation() {
        #expect(TodoCheckStyle.instant.animation == nil)
        #expect(TodoCheckStyle.draw.animation != nil)
        #expect(TodoCheckStyle.drawWithMotes.animation != nil)
        #expect(TodoDelightTiming.checkDraw == 0.25)
        #expect(TodoDelightTiming.linger == .milliseconds(1200))
    }

    @Test func motesAreDeterministicPerSeed() {
        let seed = TodoMote.seed(for: UUID(uuidString: "6F9619FF-8B86-D011-B42D-00C04FC964FF") ?? UUID())
        let a = (0..<TodoMote.count).map { TodoMote(index: $0, seed: seed) }
        let b = (0..<TodoMote.count).map { TodoMote(index: $0, seed: seed) }
        #expect(a == b)
        #expect(Set(a.map(\.angle)).count == TodoMote.count)
        #expect(TodoMote.count == 6)
    }

    @Test func motesStartAtTheEdgeAndFadeOutWithinTheirCanvas() {
        let startRadius: CGFloat = 8
        for seed: UInt64 in [0, 1, 42, .max] {
            for index in 0..<TodoMote.count {
                let mote = TodoMote(index: index, seed: seed)
                #expect(mote.opacity(at: 0) == 0)
                #expect(mote.opacity(at: 1) == 0)
                #expect(mote.opacity(at: 0.15) == 1)
                let start = mote.offset(at: 0, startRadius: startRadius)
                #expect(abs(hypot(start.width, start.height) - startRadius) < 0.001)
                // The burst canvas is 3 × the circle (48 pt): every mote stays inside it.
                let end = mote.offset(at: 1, startRadius: startRadius)
                #expect(hypot(end.width, end.height) + mote.radius < 24)
                #expect(mote.radius(at: 1) < mote.radius(at: 0))
            }
        }
    }

    @Test func motesSpreadAllAroundTheCircle() {
        let motes = (0..<TodoMote.count).map { TodoMote(index: $0, seed: 7) }
        let ups = motes.filter { sin($0.angle) < 0 }.count
        #expect(ups >= 2 && ups <= 4)
    }
}
