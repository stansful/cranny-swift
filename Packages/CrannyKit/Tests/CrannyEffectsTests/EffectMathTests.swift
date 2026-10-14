import CrannyCore
import Foundation
import SwiftUI
import Testing
@testable import CrannyEffects

// The Swift twins of the shader math (the Canvas fallbacks use them): ranges and shapes of DESIGN.md §5.3–§5.6.

@Test func motesStayInTheirColumnsAndRanges() {
    let size = CGSize(width: 880, height: 260)
    let columnWidth = size.width / 12
    for time in [0.0, 7.3, 123.4, 3599.0] {
        for column in 0..<MoteMath.columns {
            for row in 0..<MoteMath.perColumn {
                let mote = MoteMath.mote(column: column, row: row, size: size, time: time, energy: 0)
                let centre = (Double(column) + 0.5) * columnWidth
                #expect(abs(mote.center.x - centre) <= 0.3 * columnWidth + 4 + 1e-9)    // ± 30 % + 4-pt sway
                #expect(mote.center.y <= size.height + MoteMath.margin && mote.center.y > -MoteMath.margin - 1e-9)
                #expect((0.8...2.4).contains(mote.radius))
                #expect((0.55...1).contains(mote.twinkle))
                #expect(mote.stop == column * 3 + row)
            }
        }
    }
    #expect(MoteMath.count == 36)
    #expect(MoteMath.fade(0.40) == 0 && MoteMath.fade(0.60) == 1)
    #expect(MoteMath.profile(distance: 0, radius: 2) == 1.25)
}

@Test func motesRise() {
    let size = CGSize(width: 880, height: 260)
    // Over a tenth of a second every mote moves up by 0.5–1.4 pt (unless it wraps).
    for column in 0..<MoteMath.columns {
        let a = MoteMath.mote(column: column, row: 0, size: size, time: 10, energy: 0)
        let b = MoteMath.mote(column: column, row: 0, size: size, time: 10.1, energy: 0)
        let rise = a.center.y - b.center.y
        #expect((0.49...1.41).contains(rise) || rise < -size.height / 2)
    }
}

@Test func tideLinesSitAlongTheBottom() {
    let size = CGSize(width: 880, height: 260)
    for i in 0..<TideMath.lineCount {
        let line = TideMath.line(i, size: size, energy: 0)
        #expect(abs(line.base - size.height * (0.80 + 0.06 * Double(i))) < 1e-9)
        #expect(abs(line.amplitude - 3 * (1 - 0.2 * Double(i))) < 1e-9)
        for x in stride(from: 0.0, through: 880, by: 40) {
            let y = TideMath.y(line, x: x, time: 12).y
            #expect(abs(y - line.base) <= 1.45 * line.amplitude + 1e-9)
        }
    }
    #expect(TideMath.line(0, size: size, energy: 1).amplitude == 10)
    #expect(TideMath.taper(0) == 0 && TideMath.taper(1) < 1e-6 && TideMath.taper(0.5) == 1)
    #expect(abs(TideMath.strength(.vivid) - 0.8) < 1e-9)
}

@Test func embersFanOutAndGoOut() {
    let origin = CGPoint(x: 140, y: 0)
    for i in 0..<EmberMath.count {
        #expect(EmberMath.position(i, origin: origin, time: 0) == origin)
        let p = EmberMath.position(i, origin: origin, time: 0.5)
        #expect(p.y > origin.y)                                         // downward: within ±75° of straight down
        let angle = atan2(p.x - origin.x, p.y - origin.y) * 180 / .pi
        #expect(abs(angle) < 76)
        #expect((0.55...0.9).contains(EmberMath.life(i)))
        #expect((1.2...2.6).contains(EmberMath.radius(i)))
        #expect(EmberMath.brightness(i, time: 0.95) == 0)                 // every ember is out by 0.9 s
        #expect(EmberMath.brightness(i, time: 0) <= 1)
        #expect((0..<3).contains(EmberMath.stop(i, count: 3)))
        #expect(p.x >= 0 && p.x <= EmberBurst.size.width && p.y <= EmberBurst.size.height)   // stays in its frame
    }
}

@Test func sweepRunsLeadingToTrailingAndFades() {
    #expect(abs(SweepMath.head(0) + 0.1) < 1e-9 && abs(SweepMath.head(1) - 1.1) < 1e-9)
    #expect(SweepMath.light(at: 0.5, progress: 0.5) > 0.9)               // the head is at the middle half-way
    #expect(SweepMath.light(at: 0.9, progress: 0.5) < 0.01)             // nothing ahead of the head
    #expect(SweepMath.light(at: 0.35, progress: 0.5) > 0.2)             // the tail behind it
    #expect(SweepMath.light(at: 1, progress: 1) == 0)                    // faded out: no pop on removal
}

@Test func neckSnapsByTheEndOfTheSplit() {
    #expect(NeckMath.reach(7, progress: 0) == 7)
    #expect(NeckMath.reach(7, progress: 0.7) == 7)
    #expect(NeckMath.reach(7, progress: 1) == 0)
    #expect(NeckMath.reach(7, progress: 0.85) < 7 && NeckMath.reach(7, progress: 0.85) > 0)
}

@Test func firstLightRevealsEverythingByTheEnd() {
    let size = CGSize(width: 880, height: 260)
    let diagonal = (880.0 * 880 + 260 * 260).squareRoot()
    #expect(abs(FirstLightMath.reveal(elapsed: 0, size: size).radius - 0.4 * 260) < 1e-9)   // starts at the band's edge
    let end = FirstLightMath.reveal(elapsed: 1, size: size)
    #expect(abs(end.radius - diagonal * 1.6) < 1e-6)
    #expect(end.mask(atDistance: diagonal) == 1)                         // the far corners are lit when it lands
    let mid = FirstLightMath.reveal(elapsed: 0.3, size: size)
    #expect(mid.mask(atDistance: 0) == 1 && mid.mask(atDistance: mid.radius + 1) == 0)
}

@Test func typewriterRevealsInOrder() {
    #expect(TypewriterMath.opacity(index: 0, count: 10, progress: 0) == 0)
    for i in 0..<10 { #expect(TypewriterMath.opacity(index: i, count: 10, progress: 1) == 1) }
    let half = (0..<10).map { TypewriterMath.opacity(index: $0, count: 10, progress: 0.5) }
    #expect(zip(half, half.dropFirst()).allSatisfy { $0 >= $1 })        // earlier glyphs are never fainter
    #expect(TypewriterMath.duration(characters: 9, perSecond: 45, maximum: 1.2) == 0.2)
    #expect(TypewriterMath.duration(characters: 400, perSecond: 45, maximum: 1.2) == 1.2)
}

@Test func haloFallbackSamplesTheGaussian() {
    let gradient = HaloFallback.gradient(glow: .white, cap: 0.8)
    #expect(gradient.stops.count == 11)
    #expect(gradient.stops.first?.location == 0 && gradient.stops.last?.location == 1)
}
