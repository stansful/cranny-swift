// Motion choices, stagger, delights and direct manipulation (DESIGN.md §4, §5.5).
import CrannyCore
import Foundation
import SwiftUI
import CrannyEffects
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

    @Test func theStaggerIsAnEntranceOnly() {
        // When the panel opens, cards wait for their ring's turn …
        #expect(!StaggeredReveal.isShown(revealed: false, rendersFinalState: false, entrance: true))
        // … but a page that appears later (tab switch, back from the palette or the editor) is drawn at once.
        #expect(StaggeredReveal.isShown(revealed: false, rendersFinalState: false, entrance: false))
        #expect(StaggeredReveal.isShown(revealed: true, rendersFinalState: false, entrance: true))
        #expect(StaggeredReveal.isShown(revealed: false, rendersFinalState: true, entrance: true))
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

    @MainActor @Test func lifetimesAreAtMostOneSecondAndMatchCrannyEffects() {
        for moment in DelightMoment.allCases { #expect(DelightPlayback.lifetime(of: moment) <= 1.0) }
        // The playback lives exactly as long as the CrannyEffects view that draws it.
        #expect(DelightPlayback.lifetime(of: .emberBurst) == EmberBurst.duration)
        #expect(DelightPlayback.lifetime(of: .chargeSweep) == ChargeSweep.duration)
        #expect(DelightPlayback.lifetime(of: .firstLight) == FirstLight<EmptyView>.duration)
        #expect(DelightPlayback.lifetime(of: .songRipple) == 0.6)
        #expect(DelightPlayback.lifetime(of: .gulp) == 0.25)
        #expect(Gulp.swallow + Gulp.recover == 0.25 && Gulp.depth == 3)
    }

    @Test func momentsAreDrawnOnlyWhereSomeoneSeesThem() {
        func budget(onScreen: Bool = true, lowPower: Bool = false, fullScreen: Bool = false, open: Bool = false) -> EffectBudget {
            EffectBudget(isOpen: open, onScreen: onScreen, lowPower: lowPower, fullScreenFront: fullScreen,
                         reduceMotion: false, onBattery: false)
        }
        #expect(DelightPlayback.isSeen(budget()))                             // compact too (not only open)
        #expect(DelightPlayback.isSeen(budget(lowPower: true)))               // the SwiftUI design still plays
        #expect(!DelightPlayback.isSeen(budget(onScreen: false)))             // covered, locked, asleep
        #expect(!DelightPlayback.isSeen(budget(fullScreen: true, open: true)))
    }

    /// Calm and Reduce Motion draw the reduced variants (DESIGN.md §5.5, last column); Standard and Lively the moment.
    @Test func calmAndReduceMotionDrawTheReducedVariants() {
        func theme(_ motion: MotionPersonality, reduceMotion: Bool = false) -> CrannyTheme {
            var t = CrannyTheme()
            t.motion = motion
            t.reduceMotion = reduceMotion
            return t
        }
        #expect(!DelightPlayback.drawsReducedVariant(theme(.standard)) && !DelightPlayback.drawsReducedVariant(theme(.lively)))
        #expect(DelightPlayback.drawsReducedVariant(theme(.calm)))
        #expect(DelightPlayback.drawsReducedVariant(theme(.standard, reduceMotion: true)))
        #expect(DelightPlayback.drawsReducedVariant(theme(.lively, reduceMotion: true)))
        #expect(DelightPlayback.drawsReducedVariant(theme(.instant)))           // a stage that plays one anyway
    }
}

/// A swipe-down open starts the open spring at the fingers' speed (DESIGN.md §4.4).
@Suite("Swipe-down open velocity (DESIGN.md §4.4)") struct OpenVelocityTests {
    private let layout = NotchLayout(metrics: .reference)

    private func theme(_ motion: MotionPersonality = .standard, reduceMotion: Bool = false) -> CrannyTheme {
        var t = CrannyTheme()
        t.motion = motion
        t.reduceMotion = reduceMotion
        return t
    }

    @Test func theFingersSpeedBecomesAShareOfTheTravelPerSecond() {
        #expect(ShapeMotion.relativeVelocity(640, travel: 160) == 4)
        #expect(ShapeMotion.relativeVelocity(5000, travel: 160) == ShapeMotion.maximumCarry)    // a flick never throws it
        #expect(ShapeMotion.relativeVelocity(0, travel: 160) == nil)
        #expect(ShapeMotion.relativeVelocity(-300, travel: 160) == nil)
        #expect(ShapeMotion.relativeVelocity(640, travel: 0.5) == nil)                           // nothing to travel
    }

    @Test func theOpenSpringStartsWithTheVelocity() {
        let from = layout.closed, to = layout.open(columns: 10)
        let travel = to.bottom - from.bottom
        let velocity = 4 * travel
        #expect(ShapeMotion.openAnimation(velocity: velocity, from: from, to: to, theme: theme())
                == .interpolatingSpring(duration: 0.42, bounce: 0.14, initialVelocity: 4))
        // The personality scales the bounce as for every spring: Calm lands without overshoot, Lively bounces more.
        #expect(ShapeMotion.openAnimation(velocity: velocity, from: from, to: to, theme: theme(.calm))
                == .interpolatingSpring(duration: 0.42, bounce: 0, initialVelocity: 4))
        #expect(ShapeMotion.openAnimation(velocity: velocity, from: from, to: to, theme: theme(.lively))
                == .interpolatingSpring(duration: 0.42, bounce: 0.14 * 1.5, initialVelocity: 4))
    }

    @Test func reduceMotionAndInstantIgnoreIt() {
        let from = layout.compact(.short), to = layout.open(columns: 10)
        let reduced = theme(reduceMotion: true)
        #expect(ShapeMotion.openAnimation(velocity: 900, from: from, to: to, theme: reduced)
                == ShapeMotion.animation(.open, theme: reduced))                // the dissolve at the final size
        #expect(ShapeMotion.openAnimation(velocity: 900, from: from, to: to, theme: theme(.instant)) == nil)
        #expect(ShapeMotion.openAnimation(velocity: 0, from: from, to: to, theme: theme())
                == ShapeMotion.animation(.open, theme: theme()))
    }

    @Test func theOpenStateCarriesItOnlyWhenGiven() {
        #expect(OpenState(page: .nook, reason: .click).gestureVelocity == 0)
        #expect(OpenState(page: .nook, reason: .swipe, gestureVelocity: 640).gestureVelocity == 640)
    }
}

/// The charge sweep runs along the lower outline of the shape (`LowerRim.outline`), inside it.
@Suite("Charge sweep outline (DESIGN.md §5.1, §5.5)") struct ChargeSweepOutlineTests {
    @Test(arguments: [NotchLayout(metrics: .reference).compact(.short),
                      NotchLayout(metrics: NotchMetrics(hasNotch: false, notchWidth: 0, bandHeight: 30, screenWidth: 1920),
                                  noNotchStyle: .floatingIsland).compact(.medium)])                        // a floating island
    func leadingToTrailingInsideTheShape(geometry g: NotchGeometry) throws {
        let canvas = CGRect(x: 0, y: 0, width: 480, height: 80)
        let outline = LowerRim.outline(g, in: canvas)
        let shape = NotchShape(g).path(in: canvas)
        let points = samples(of: outline)
        let first = try #require(points.first), last = try #require(points.last)
        // From the leading side at the body's middle to the trailing side's middle …
        #expect(abs(first.x - (canvas.midX - g.bodyWidth / 2 + StrokeWidth.rim / 2)) < 0.01)
        #expect(abs(last.x - (canvas.midX + g.bodyWidth / 2 - StrokeWidth.rim / 2)) < 0.01)
        #expect(abs(first.y - (g.topInset + g.height / 2)) < 0.01 && abs(last.y - first.y) < 0.01)
        // … left to right (x never goes back), along the bottom, and half a rim inside the shape everywhere.
        #expect(zip(points, points.dropFirst()).allSatisfy { $1.x >= $0.x - 0.001 })
        #expect(abs((points.map(\.y).max() ?? 0) - (g.bottom - StrokeWidth.rim / 2)) < 0.01)
        for p in points {
            #expect(shape.contains(p), "\(p) is outside the shape")
        }
    }

    @Test func noOutlineForAShapeTooSmallToHaveOne() {
        #expect(LowerRim.outline(.zero, in: CGRect(x: 0, y: 0, width: 100, height: 40)).isEmpty)
    }

    /// The path's end points and its curves sampled 8 times each.
    private func samples(of path: Path) -> [CGPoint] {
        var points: [CGPoint] = [], current = CGPoint.zero
        path.forEach { element in
            switch element {
            case .move(let p), .line(let p):
                points.append(p); current = p
            case .curve(let p, let c1, let c2):
                for i in 1...8 {
                    let t = CGFloat(i) / 8, u = 1 - t
                    let x = u * u * u * current.x + 3 * u * u * t * c1.x + 3 * u * t * t * c2.x + t * t * t * p.x
                    let y = u * u * u * current.y + 3 * u * u * t * c1.y + 3 * u * t * t * c2.y + t * t * t * p.y
                    points.append(CGPoint(x: x, y: y))
                }
                current = p
            case .quadCurve(let p, _):
                points.append(p); current = p
            case .closeSubpath:
                break
            }
        }
        return points
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
