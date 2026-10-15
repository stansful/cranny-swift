import CoreGraphics
import CrannyCore
import Foundation
import SwiftUI
import Testing
@testable import CrannyEffects

// The ambient layer's drawable (AmbientDrawableLayout.swift): only the lit band, in place, so its pixels are exactly
// those of a drawable of the whole layer; while resizing it grows in steps and keeps what it has.

@Test func restingDrawableIsExactlyTheLitBand() throws {
    let layout = try #require(AmbientDrawableLayout(bounds: CGSize(width: 656, height: 170), scale: 2, litTop: 61))
    #expect(layout.offset == 122)
    #expect(layout.pixels == CGSize(width: 1312, height: 340 - 122))
    #expect(layout.region == layout.pixels && !layout.hasSlack)
    #expect(layout.frame == CGRect(x: 0, y: 0, width: 656, height: 109), "the band sits at the bottom of the view")
    // No clear rows (the halo), fractional points and degenerate sizes.
    let halo = try #require(AmbientDrawableLayout(bounds: CGSize(width: 300, height: 100), scale: 1, litTop: 0))
    #expect(halo.offset == 0 && halo.pixels == CGSize(width: 300, height: 100) && halo.frame.origin == .zero)
    let morphing = try #require(AmbientDrawableLayout(bounds: CGSize(width: 300.3, height: 100.6), scale: 2, litTop: 20))
    #expect(morphing.pixels == CGSize(width: 601, height: 201 - 40), "the whole view's drawable, rounded, minus the clear rows")
    #expect(abs(morphing.frame.maxY - (100.6 - 40 * 100.6 / 201)) < 1e-9,
            "a pixel covers as many points as when the whole drawable was stretched over the bounds")
    #expect(abs(morphing.frame.width - 300.3) < 1e-9 && abs(morphing.frame.minY) < 1e-9, "stretched to the bounds")
    #expect(AmbientDrawableLayout(bounds: CGSize(width: 0.5, height: 100), scale: 2, litTop: 0) == nil)
    let tiny = try #require(AmbientDrawableLayout(bounds: CGSize(width: 10, height: 2), scale: 1, litTop: 40))
    #expect(tiny.offset == 1 && tiny.pixels.height == 1, "at least one row is drawn")
}

@Test func resizingDrawableGrowsInStepsAndKeepsItsSize() throws {
    let start = try #require(AmbientDrawableLayout(bounds: CGSize(width: 400, height: 100), scale: 1, litTop: 30))
    #expect(start.pixels == CGSize(width: 400, height: 70))
    // Larger than the drawable: grown to the next 64-pixel step, the band itself is the region the shader fills.
    let grown = try #require(AmbientDrawableLayout(bounds: CGSize(width: 410, height: 104), scale: 1, litTop: 32,
                                                   growingFrom: start.pixels))
    #expect(grown.pixels == CGSize(width: 448, height: 128))
    #expect(grown.region == CGSize(width: 410, height: 72) && grown.hasSlack)
    #expect(abs(grown.frame.maxY - (104 - 32)) < 1e-9 && grown.frame.width == 448)
    // Smaller again (the close morph): the drawable is kept.
    let shrunk = try #require(AmbientDrawableLayout(bounds: CGSize(width: 380, height: 90), scale: 1, litTop: 26,
                                                    growingFrom: grown.pixels))
    #expect(shrunk.pixels == grown.pixels && shrunk.region == CGSize(width: 380, height: 64))
    // At rest: exact again.
    let rest = try #require(AmbientDrawableLayout(bounds: CGSize(width: 380, height: 90), scale: 1, litTop: 26))
    #expect(rest.pixels == rest.region && !rest.hasSlack)
}

/// The clear rows above the band are clear for every effect, at the ripple's energy pulse and while the ripple plays,
/// so leaving them out of the drawable changes nothing.
@Test(.enabled(if: shadersRun), arguments: AmbientEffect.allCases)
func litTopIsAlwaysClear(_ effect: AmbientEffect) throws {
    let renderer = try #require(AmbientRenderer.renderer(forDisplay: nil))
    let size = CGSize(width: 600, height: 200), scale: CGFloat = 2
    let (w, h) = (Int(size.width * scale), Int(size.height * scale))
    let date = Date(timeIntervalSinceReferenceDate: 5000)
    for energy in [0.0, 1.5] {
        for ripple in [nil, 0.1] as [Double?] {                         // 0.1 s: the wave's largest displacement
            var state = layerState(effect, level: .vivid, energy: energy)
            state.rippleStart = ripple.map { date.addingTimeInterval(-$0) }
            for time in [3.0, 2900.0] {
                let uniforms = AmbientUniforms(state: state, size: size, scale: scale, time: time, date: date)
                let bgra = try #require(renderer.image(effect, uniforms: uniforms, width: w, height: h))
                let rows = Int(AmbientRenderer.litTop(effect, height: size.height, energy: energy) * scale)
                let lit = bgra.withUnsafeBufferPointer { bytes in
                    stride(from: 3, to: rows * w * 4, by: 4).contains { bytes[$0] != 0 }
                }
                #expect(!lit, "\(effect) energy \(energy) ripple \(String(describing: ripple)) t\(time): a clear row is lit")
            }
        }
    }
    #expect(AmbientRenderer.litTop(.halo, height: 260, energy: 0) == 0)
    #expect(AmbientRenderer.litTop(.aurora, height: 260, energy: 0) > 0.35 * 260)
    #expect(AmbientRenderer.litTop(.tide, height: 260, energy: 0) > 0.6 * 260)
    #expect(AmbientRenderer.litTop(.tide, height: 260, energy: 0) == AmbientRenderer.litTop(.tide, height: 260, energy: 1))
}

/// A drawable of the band only (`counts.y` rows above it) holds exactly the bottom rows of a drawable of the whole
/// layer: the same field, fill, reveal, ripple and dither, bit for bit.
@Test(.enabled(if: shadersRun), arguments: AmbientEffect.allCases)
func bandDrawableMatchesTheWholeLayer(_ effect: AmbientEffect) throws {
    let renderer = try #require(AmbientRenderer.renderer(forDisplay: nil))
    let size = CGSize(width: 440, height: 130), scale: CGFloat = 2
    let date = Date(timeIntervalSinceReferenceDate: 5000)
    var state = layerState(effect, level: .vivid, energy: 0.6, fill: 0.5)        // the fill masks the band's top rows
    state.reveal = AmbientReveal(center: .top, radius: 200, feather: 90)            // and the reveal its far corners
    state.rippleStart = date.addingTimeInterval(-0.2)
    let (w, h) = (Int(size.width * scale), Int(size.height * scale))
    let offset = Int(AmbientRenderer.litTop(effect, height: size.height, energy: state.energy) * scale)
    let whole = AmbientUniforms(state: state, size: size, scale: scale, time: 17, date: date)
    let band = AmbientUniforms(state: state, size: size, scale: scale, time: 17, date: date, rowOffset: offset)
    let full = try #require(renderer.image(effect, uniforms: whole, width: w, height: h))
    let part = try #require(renderer.image(effect, uniforms: band, width: w, height: h - offset))
    #expect(Array(full[(offset * w * 4)...]) == part, "\(effect): the band differs from the whole layer's rows")
    #expect(full.contains { $0 != 0 }, "\(effect): nothing drawn")
}

/// A drawable left larger by a resize holds the band and one pixel past it (Core Animation's filter reads that pixel
/// at the light's bottom and right edges) exactly as an exact drawable would, and nothing beyond.
@Test(.enabled(if: shadersRun)) func slackDrawableFillsTheBandAndTheFilterMargin() throws {
    let renderer = try #require(AmbientRenderer.renderer(forDisplay: nil))
    let size = CGSize(width: 100, height: 60)
    let uniforms = AmbientUniforms(state: layerState(.halo, level: .vivid), size: size, scale: 1, time: 3,
                                   date: Date(timeIntervalSinceReferenceDate: 5000))   // the halo lights every pixel
    let margin = AmbientRenderer.filterMargin
    let (w, h) = (100 + margin, 60 + margin), (slackW, slackH) = (128, 64)
    let exact = try #require(renderer.image(.halo, uniforms: uniforms, width: w, height: h))
    let slack = try #require(renderer.image(.halo, uniforms: uniforms, width: slackW, height: slackH, region: size))
    #expect(exact[((h - 1) * w + w - 1) * 4 + 3] != 0, "the margin's corner pixel is lit")
    var mismatches = 0, litOutside = 0
    for row in 0..<slackH {
        for column in 0..<slackW {
            let alpha = slack[(row * slackW + column) * 4 + 3]
            if row < h, column < w {
                let i = (row * w + column) * 4, j = (row * slackW + column) * 4
                if exact[i..<i + 4] != slack[j..<j + 4] { mismatches += 1 }
            } else if alpha != 0 {
                litOutside += 1
            }
        }
    }
    #expect(mismatches == 0, "\(mismatches) pixels of the band and its margin differ from an exact drawable")
    #expect(litOutside == 0, "\(litOutside) pixels beyond the margin are lit")
}

// MARK: - Per-frame tables (AmbientFrameTables.swift)

@Test func frameTablesRoundStopsLikeTheShader() {
    #expect(AmbientFrameTables.halfRounded(1) == 1)
    #expect(AmbientFrameTables.halfRounded(0) == 0)
    #expect(AmbientFrameTables.halfRounded(0.1) == 0.0999755859375)                    // 1638 · 2⁻¹⁴
    #expect(AmbientFrameTables.halfRounded(1 + 0.5 / 1024) == 1, "ties go to even")
    #expect(AmbientFrameTables.halfRounded(1 + 1.5 / 1024) == 1 + 2.0 / 1024)
    #if arch(arm64)
    for i in 0...1000 {
        let x = Float(i) / 1000
        #expect(AmbientFrameTables.halfRounded(x) == Float(Float16(x)), "\(x)")
    }
    #endif
}

@Test func frameTablesMatchTheirTwins() {
    var state = layerState(.motes, palette: .afterglow, level: .vivid, energy: 0.4)
    let u = AmbientUniforms(state: state, size: CGSize(width: 880, height: 260), scale: 2, time: 12.5, date: Date())
    var motes: [SIMD4<Float>] = []
    AmbientFrameTables.motes(u, into: &motes)
    #expect(motes.count == 2 * MoteMath.count && motes.count * 16 <= 4096)
    let mote = MoteMath.mote(column: 5, row: 2, size: CGSize(width: 880, height: 260), time: 12.5, energy: Double(Float(0.4)))
    let entry = motes[2 * 17]
    #expect(abs(Double(entry.x) - mote.center.x) < 1e-3 && abs(Double(entry.y) - mote.center.y) < 1e-3)
    #expect(abs(Double(entry.z) - mote.radius) < 1e-6 && abs(Double(entry.w) - mote.twinkle) < 1e-6)
    #expect(motes[2 * 17 + 1] == SIMD4(u.stops.2.x, u.stops.2.y, u.stops.2.z, 0), "mote 17 takes stop 17 mod 3")
    // OKLab: white is (1, 0, 0), black 0; the aurora's three stops follow the palette modulo its count.
    let white = AmbientFrameTables.oklab(SIMD3(1, 1, 1))
    #expect(abs(white.x - 1) < 1e-4 && abs(white.y) < 1e-4 && abs(white.z) < 1e-4)
    #expect(AmbientFrameTables.oklab(.zero) == .zero)
    state.glows = [.white, .black]
    var lab: [SIMD4<Float>] = []
    AmbientFrameTables.auroraLab(AmbientUniforms(state: state, size: CGSize(width: 10, height: 10), scale: 1, time: 0,
                                                 date: Date()), into: &lab)
    #expect(lab.count == 3 && lab[2] == lab[0] && lab[1] == .zero)
    state.glows = []
    AmbientFrameTables.auroraLab(AmbientUniforms(state: state, size: CGSize(width: 10, height: 10), scale: 1, time: 0,
                                                 date: Date()), into: &lab)
    #expect(lab == [.zero, .zero, .zero])
}
