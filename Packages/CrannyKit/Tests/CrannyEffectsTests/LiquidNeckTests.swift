import CoreGraphics
import CrannyCore
import Foundation
import SwiftUI
import Testing
@testable import CrannyEffects

// The satellite split (DESIGN.md §5.6 `liquidNeck`): one surface that thins and snaps, on both paths. Rendered at 2×
// (the shader's anti-aliasing is sized for Retina) over the whole split, so a transient artifact cannot hide
// between two sampled frames.

private let size = CGSize(width: 180, height: 48)

/// Capsule 120 × 32 and a 32-pt bubble moving from x 112 to 126 (the module's preview): the bodies overlap until
/// progress 0.57, then a gap opens and widens to 6 pt.
private struct CapsuleAndBubble: View {
    var progress: Double
    var body: some View {
        ZStack(alignment: .leading) {
            Capsule().fill(.black).frame(width: 120, height: 32)
            Circle().fill(.black).frame(width: 32, height: 32).offset(x: 112 + 14 * progress)
        }
        .frame(width: size.width, height: size.height)
    }
}

/// The compact shape's trailing end (square top corner, 10-pt bottom radius) and a 24-pt bubble budding 30 pt out.
private struct TrailingEndAndBubble: View {
    var progress: Double
    var body: some View {
        ZStack(alignment: .leading) {
            UnevenRoundedRectangle(cornerRadii: .init(topLeading: 0, bottomLeading: 10, bottomTrailing: 10, topTrailing: 0))
                .fill(.black).frame(width: 100, height: 32)
            Circle().fill(.black).frame(width: 24, height: 24).offset(x: 76 + 30 * progress)
        }
        .frame(width: size.width, height: size.height)
    }
}

private let lowPower = EffectBudget(isOpen: true, onScreen: true, lowPower: true, fullScreenFront: false,
                                    reduceMotion: false, onBattery: false)

@MainActor private func neck(_ bodies: some View, progress: Double, shader: Bool) throws -> Raster {
    try rasterize(LiquidNeck(progress: progress, budget: shader ? runningBudget : lowPower) { bodies },
                  size: size, scale: 2)
}

/// Progress values over the whole split: every 0.05, and every 0.01 where the neck thins and snaps.
private let progressSteps: [Double] = Array(stride(from: 0.0, to: 0.8, by: 0.05)) + Array(stride(from: 0.8, through: 1.0, by: 0.01))

/// The progress at which the bodies come apart (the first frame with two pieces), after checking that the surface is
/// one piece before it and exactly two after it: no floating fragment, no re-joining.
@MainActor private func snapProgress<Bodies: View>(shader: Bool, bodies: (Double) -> Bodies) throws -> Double? {
    var snap: Double?
    for progress in progressSteps {
        let pieces = try neck(bodies(progress), progress: progress, shader: shader).components()
        #expect(pieces <= 2, "\(shader ? "shader" : "Canvas") at \(progress): \(pieces) pieces (a floating fragment)")
        if snap == nil, pieces == 2 { snap = progress }
        if snap != nil { #expect(pieces == 2, "\(shader ? "shader" : "Canvas") at \(progress): joined again") }
    }
    return snap
}

/// One piece, then two, never more, on both paths, and both paths let go at the same moment (finding: the old
/// bridge term left a floating sliver at 0.85, and the Canvas let go far earlier than the shader).
@Test(.enabled(if: shadersRun)) func liquidNeckSnapsOnceWithoutFragments() throws {
    let shader = try #require(try snapProgress(shader: true) { CapsuleAndBubble(progress: $0) })
    let canvas = try #require(try snapProgress(shader: false) { CapsuleAndBubble(progress: $0) })
    // The bodies' own gap opens at 0.57; the neck holds it closed well beyond that and snaps before the end.
    #expect(shader > 0.75 && shader < 1, "shader snaps at \(shader)")
    #expect(abs(shader - canvas) <= 0.03, "shader snaps at \(shader), Canvas at \(canvas)")
    let shaderEnd = try #require(try snapProgress(shader: true) { TrailingEndAndBubble(progress: $0) })
    let canvasEnd = try #require(try snapProgress(shader: false) { TrailingEndAndBubble(progress: $0) })
    #expect(abs(shaderEnd - canvasEnd) <= 0.03, "trailing end: shader \(shaderEnd), Canvas \(canvasEnd)")
}

/// The neck's outline is smooth: across the gap, the top edge goes down into the neck and back up once (a crown of
/// spikes or a notch would turn it several times).
@Test(.enabled(if: shadersRun)) func liquidNeckOutlineIsSmooth() throws {
    for progress in progressSteps where progress < 0.89 {
        let r = try neck(CapsuleAndBubble(progress: progress), progress: progress, shader: true)
        // Columns from the capsule's round end (x 136 pt) to the bubble's centre, in pixels.
        let columns = Array(272..<Int(2 * (156 + 14 * progress)))
        let tops = columns.map { r.topEdge(column: $0) }
        var turns = 0, direction = 0, anchor = tops[0]
        for top in tops.dropFirst() where abs(top - anchor) >= 0.3 {
            let step = top > anchor ? 1 : -1
            if direction != 0, step != direction { turns += 1 }
            direction = step
            anchor = top
        }
        #expect(turns <= 1, "progress \(progress): the top edge turns \(turns) times")
    }
}

/// A lone body is drawn exactly as it is: the neck never swells or erodes a shape that has nothing to join.
@Test(.enabled(if: shadersRun)) func liquidNeckLeavesALoneBodyAlone() throws {
    let lone = Capsule().fill(.black).frame(width: 120, height: 32).frame(width: size.width, height: size.height)
    let plain = try rasterize(lone, size: size, scale: 2)
    for shader in [true, false] {
        let r = try neck(lone, progress: 0.5, shader: shader)
        #expect(r.meanDifference(plain) < 0.05, "\(shader ? "shader" : "Canvas"): \(r.meanDifference(plain))")
    }
}

/// Two boxes 6 pt apart: joined early in the split (6 < 2 · reach), apart at the end, on both paths.
@Test(.enabled(if: shadersRun)) func liquidNeckJoinsThenSnaps() throws {
    let boxes = HStack(spacing: 6) {
        Rectangle().fill(.black).frame(width: 40, height: 30)
        Rectangle().fill(.black).frame(width: 40, height: 30)
    }
    .frame(width: size.width, height: size.height)
    for shader in [true, false] {
        let early = try neck(boxes, progress: 0.1, shader: shader)
        let late = try neck(boxes, progress: 1, shader: shader)
        #expect(early.alpha(180, 48) > 0.9, "\(shader ? "shader" : "Canvas"): no neck early on")
        #expect(early.components() == 1)
        #expect(late.alpha(180, 48) < 0.1, "\(shader ? "shader" : "Canvas"): the neck did not snap")
        #expect(late.components() == 2)
    }
}

@Test func neckSamplesFarEnoughForItsChords() {
    #expect(NeckMath.maxSampleOffset(7) == CGSize(width: 15, height: 15))     // chords up to 2 · reach + subsamples
}
