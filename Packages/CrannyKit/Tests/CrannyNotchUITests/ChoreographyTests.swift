// Motion choices, stagger, delights and direct manipulation (DESIGN.md §4, §5.5).
import CrannyCore
import Foundation
import SwiftUI
import Testing
@testable import CrannyNotchUI

private func kind(_ from: NotchPhase, _ to: NotchPhase, fromHUD: Bool = false, toHUD: Bool = false) -> CrannyMotion.Kind {
    ShapeMotion.kind(from: ShapeMotionState(phase: from, isHUD: fromHUD), to: ShapeMotionState(phase: to, isHUD: toHUD))
}

@Suite("Shape motion (DESIGN.md §4.1 table)") struct ShapeMotionTests {
    @Test func growsWithBounceLandsWithout() {
        #expect(kind(.idle, .open) == .open)
        #expect(kind(.compact, .open) == .open)
        #expect(kind(.peek, .open) == .open)
        #expect(kind(.open, .idle) == .close)
        #expect(kind(.open, .compact) == .close)
        #expect(kind(.open, .open) == .resize)
        #expect(kind(.idle, .compact) == .activityIn)
        #expect(kind(.compact, .idle) == .activityOut)
        #expect(kind(.compact, .compact) == .activitySwap)
        #expect(kind(.compact, .peek) == .peekIn)
        #expect(kind(.peek, .compact) == .peekOut)
        #expect(kind(.peek, .idle) == .close)
        #expect(kind(.idle, .breath) == .hoverIn)
        #expect(kind(.breath, .idle) == .hoverOut)
        #expect(kind(.idle, .hidden) == .close)
    }

    @Test func hudEntersAndLeavesWithItsOwnSprings() {
        #expect(kind(.idle, .compact, toHUD: true) == .hudIn)
        #expect(kind(.compact, .compact, toHUD: true) == .hudIn)               // Now Playing → HUD
        #expect(kind(.compact, .compact, fromHUD: true) == .hudOut)            // HUD → Now Playing
        #expect(kind(.compact, .idle, fromHUD: true) == .hudOut)
        #expect(kind(.compact, .compact, fromHUD: true, toHUD: true) == .activitySwap)   // later presses: the shape stays
    }

    @Test func everyKindThatShrinksLandsWithZeroBounce() {
        for (from, to) in [(NotchPhase.open, NotchPhase.idle), (.compact, .idle), (.peek, .compact), (.breath, .idle)] {
            let k = kind(from, to)
            #expect(CrannyMotion.spec(k).lands, "\(k) must land")
        }
    }

    @Test func closeStartsAfterTheContentLeft() {
        #expect(ShapeMotion.delay(for: .close, reduceMotion: false) == 0.04)
        #expect(ShapeMotion.delay(for: .close, reduceMotion: true) == 0)
        #expect(ShapeMotion.delay(for: .open, reduceMotion: false) == 0)
    }

    @Test func reduceMotionCrossFadesOnlyBigMorphs() {
        let morph = ShapeMotion.crossFadeKey(phase: .open, reduceMotion: false)
        #expect(morph == ShapeMotion.crossFadeKey(phase: .idle, reduceMotion: false))
        // Reduce Motion: closed ⇄ compact ⇄ peek morph (same key) …
        let band = ShapeMotion.crossFadeKey(phase: .compact, reduceMotion: true)
        #expect(band == ShapeMotion.crossFadeKey(phase: .peek, reduceMotion: true))
        #expect(band == ShapeMotion.crossFadeKey(phase: .idle, reduceMotion: true))
        // … open and close cross-fade the whole surface (new key) …
        #expect(ShapeMotion.crossFadeKey(phase: .open, reduceMotion: true) != band)
        // … and a resize keeps the surface: no travel, `ResizeCrossFade` dissolves the outlines.
        var reduced = CrannyTheme()
        reduced.reduceMotion = true
        #expect(ShapeMotion.animation(.resize, theme: reduced) == nil)
        #expect(ShapeMotion.animation(.open, theme: reduced) != nil)        // drives the open cross-fade
        #expect(ShapeMotion.animation(.resize, theme: CrannyTheme()) != nil)
    }

    @Test func instantHasNoAnimation() {
        var theme = CrannyTheme()
        theme.motion = .instant
        #expect(ShapeMotion.animation(.open, theme: theme) == nil)
        #expect(theme.contentIn(after: 0.1) == nil)
    }
}

@Suite("Stagger (DESIGN.md §4.3, §4.5)") struct StaggerTests {
    @Test func ringsRadiateFromTheWidgetUnderTheCamera() {
        #expect(Stagger.rings(cells: [5, 3, 2]) == [0, 0, 1])           // centre (5) on the gutter after Media
        #expect(Stagger.rings(cells: [4, 3, 2, 1]) == [1, 0, 1, 2])     // centre inside the 2nd widget
        #expect(Stagger.rings(cells: [2, 2, 2, 2, 2]) == [2, 1, 0, 1, 2])
        #expect(Stagger.rings(cells: [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1]) == [4, 4, 4, 3, 2, 1, 0, 1, 2, 3, 4, 4, 4])
        #expect(Stagger.rings(cells: []) == [])
        #expect(Stagger.rings(cells: [6]) == [0])
    }

    @Test func eighteenMillisecondsPerRingNoneUnderReduceMotion() {
        #expect(Stagger.delay(ring: 0, reduceMotion: false) == 0)
        #expect(abs(Stagger.delay(ring: 2, reduceMotion: false) - 0.036) < 1e-9)
        #expect(abs(Stagger.delay(ring: 9, reduceMotion: false) - 0.072) < 1e-9)
        #expect(Stagger.delay(ring: 3, reduceMotion: true) == 0)
    }

    @Test func wingsGrowAfterTheShapeAndReturnLateOnClose() {
        #expect(ContentTiming.slotDelay(after: .activityIn) == 0.08)
        #expect(ContentTiming.slotDelay(after: .activitySwap) == 0.08)
        #expect(ContentTiming.slotDelay(after: .close) == 0.22)                  // open → compact
    }

    @Test func peekRowsThirtyMillisecondsTopToBottom() {
        #expect(ContentTiming.peekRowDelay(index: 0, reduceMotion: false) == 0)
        #expect(abs(ContentTiming.peekRowDelay(index: 2, reduceMotion: false) - 0.06) < 1e-9)
        #expect(ContentTiming.peekRowDelay(index: 2, reduceMotion: true) == 0)
    }
}

@Suite("Edit-mode wiggle (DESIGN.md §6.6)") struct WiggleTests {
    @Test func oneDegreeOutOfPhaseRestingWhilePaused() {
        #expect(Wiggle.angle(time: nil, index: 3) == 0)                         // paused clock: the card rests
        let samples = stride(from: 0.0, to: 2, by: 0.01).map { Wiggle.angle(time: $0, index: 0) }
        #expect(samples.allSatisfy { abs($0) <= 1 } && (samples.max() ?? 0) > 0.99)
        #expect(Wiggle.angle(time: 0.4, index: 0) != Wiggle.angle(time: 0.4, index: 1))   // neighbours out of phase
    }
}

@Suite("Delight moments (DESIGN.md §5.5)") struct DelightTests {
    @Test func eachSerialPlaysOnce() {
        #expect(DelightPlayback.shouldPlay(moment: .gulp, serial: 3, lastPlayed: 2))
        #expect(!DelightPlayback.shouldPlay(moment: .gulp, serial: 2, lastPlayed: 2))     // already played
        #expect(!DelightPlayback.shouldPlay(moment: nil, serial: 3, lastPlayed: 2))       // nothing named
        #expect(!DelightPlayback.shouldPlay(moment: .emberBurst, serial: 1, lastPlayed: 5))
    }

    @Test func lifetimesAreAtMostOneSecond() {
        for moment in DelightMoment.allCases { #expect(DelightPlayback.lifetime(of: moment) <= 1.0) }
        #expect(DelightPlayback.lifetime(of: .emberBurst) == 0.9)
        #expect(DelightPlayback.lifetime(of: .songRipple) == 0.6)
        #expect(DelightPlayback.lifetime(of: .gulp) == 0.25)
        let start = Date(timeIntervalSinceReferenceDate: 100)
        let playback = DelightPlayback(moment: .chargeSweep, serial: 1, startedAt: start)
        #expect(abs(playback.progress(at: start.addingTimeInterval(0.4)) - 0.5) < 1e-6)
        #expect(playback.progress(at: start.addingTimeInterval(5)) == 1)
        #expect(Gulp.swallow + Gulp.recover == 0.25 && Gulp.depth == 3)
    }

    @Test func momentsRunAtTheBudgetRateAndPauseWhenUnseen() {
        func budget(onScreen: Bool = true, lowPower: Bool = false, fullScreen: Bool = false, battery: Bool = false) -> EffectBudget {
            EffectBudget(isOpen: false, onScreen: onScreen, lowPower: lowPower, fullScreenFront: fullScreen,
                         reduceMotion: true, onBattery: battery)
        }
        #expect(DelightPlayback.frameInterval(budget()) == 1.0 / 30)                  // compact too (not only open)
        #expect(DelightPlayback.frameInterval(budget(battery: true)) == 1.0 / 20)
        #expect(DelightPlayback.frameInterval(budget(lowPower: true)) == 1.0 / 30)    // the SwiftUI design still plays
        #expect(DelightPlayback.frameInterval(budget(onScreen: false)) == nil)        // covered, locked, asleep
        #expect(DelightPlayback.frameInterval(budget(fullScreen: true)) == nil)
    }

    @Test func embersAreStatelessFanDownAndDie() {
        let size = EmberBurstView.size
        let a = EmberField.ember(7, time: 0.3, size: size, stopCount: 3)
        #expect(a == EmberField.ember(7, time: 0.3, size: size, stopCount: 3))          // pure function of time + seed
        var alive = 0
        for i in 0..<EmberField.count {
            if let e = EmberField.ember(i, time: 0.25, size: size, stopCount: 3) {
                alive += 1
                #expect(e.position.y > 0)                                              // below the shape's edge
                #expect(abs(e.position.x - size.width / 2) <= e.position.y * tan(75 * .pi / 180) + 1)   // within ±75°
                #expect((0...1).contains(e.alpha))
                #expect((1.2...2.6).contains(e.radius) && (0..<3).contains(e.stop))
            }
        }
        #expect(alive == EmberField.count)
        #expect((0..<EmberField.count).allSatisfy { EmberField.ember($0, time: 0.95, size: size, stopCount: 3) == nil })
    }

    @Test func chargeSweepHeadTravelsLeadingToTrailing() {
        #expect(abs(ChargeSweepProfile.head(progress: 0) - -0.1) < 1e-9)
        #expect(abs(ChargeSweepProfile.head(progress: 1) - 1.1) < 1e-9)
        #expect(ChargeSweepProfile.light(at: 0.5, progress: 0.5) > 0.99)               // the head
        #expect(ChargeSweepProfile.light(at: 0.9, progress: 0.5) < 0.01)               // ahead of it: dark
        let tail = ChargeSweepProfile.light(at: 0.35, progress: 0.5)
        #expect(tail > 0.05 && tail < 0.5)                                             // a fading tail behind it
        #expect(ChargeSweepProfile.stops(progress: 0.3).count == 25)
    }
}

@Suite("Direct manipulation (DESIGN.md §4.4)") struct GestureFollowTests {
    @Test func swipeDownGrowsTheClosedAndCompactShape() {
        let layout = NotchLayout(metrics: .reference)
        let g = CanvasGeometry.adjusted(layout.closed, phase: .idle, gesture: CGSize(width: 0, height: 12), gulp: 0)
        #expect(g.height == layout.closed.height + 12)
        let up = CanvasGeometry.adjusted(layout.closed, phase: .compact, gesture: CGSize(width: 0, height: -12), gulp: 0)
        #expect(up.height == layout.closed.height)                                      // up lifts content instead
        #expect(GestureFollow.contentOffset(CGSize(width: 8, height: -10), phase: .compact) == CGSize(width: 8, height: -10))
        #expect(GestureFollow.contentOffset(CGSize(width: 8, height: 10), phase: .peek) == CGSize(width: 8, height: 0))
        #expect(GestureFollow.contentOffset(CGSize(width: 8, height: 10), phase: .open) == .zero)
    }

    @Test func theOpenShapeFollowsASwipeUpAtMostTwentyPoints() {
        let open = NotchLayout(metrics: .reference).open(columns: 10)
        #expect(CanvasGeometry.adjusted(open, phase: .open, gesture: CGSize(width: 0, height: -8), gulp: 0).height == 162)
        #expect(CanvasGeometry.adjusted(open, phase: .open, gesture: CGSize(width: 0, height: -80), gulp: 0).height == 150)
        #expect(CanvasGeometry.adjusted(open, phase: .open, gesture: CGSize(width: 0, height: 30), gulp: 0).height == 170)
        #expect(CanvasGeometry.adjusted(open, phase: .open, gesture: .zero, gulp: -3).height == 167)     // the gulp
    }

    @MainActor @Test func aHiddenNotchFadesInsteadOfShrinking() {
        let model = NotchSceneModel(layout: NotchLayout(metrics: .reference), theme: CrannyTheme())
        model.phase = .hidden
        #expect(model.geometry == .zero)                                               // the shell's hit area: nothing
        #expect(CanvasGeometry.base(model) == model.layout.closed)                     // drawn at alpha 0
    }
}
