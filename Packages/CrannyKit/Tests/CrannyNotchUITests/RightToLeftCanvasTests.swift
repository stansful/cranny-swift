// The canvas in a right-to-left language (Arabic, Hebrew; ARCHITECTURE.md §8.7): the notch stays centred on the camera
// and symmetric, the wings and the satellite swap sides with the layout, the playback rim keeps running left to right,
// and content that follows the fingers moves with them.
import CrannyCore
import Foundation
import SwiftUI
import Testing
@testable import CrannyNotchUI

@MainActor private func scene(_ phase: NotchPhase, sample: PreviewActivity.Sample = .nowPlaying, satellite: Bool = false)
    -> (NotchSceneModel, ModuleRegistry) {
    let (model, registry) = previewScene(phase, metrics: PreviewDisplays.notch, sample: sample, satellite: satellite)
    var theme = model.theme
    theme.ambience = .off                                  // measure the shape, not the light inside it
    model.theme = theme
    return (model, registry)
}

@MainActor @Suite("Canvas right to left") struct RightToLeftCanvasTests {
    /// The shapes are the camera's, whatever the language: the same rows at the same places.
    @Test func theShapeStaysOnTheCamera() throws {
        for phase in [NotchPhase.idle, .compact, .open] {
            let (model, registry) = scene(phase)
            let ltr = try #require(Snapshot.probe(model, registry))
            let rtl = try #require(Snapshot.probe(model, registry, layoutDirection: .rightToLeft))
            let (a, b) = (try #require(ltr.verticalExtent), try #require(rtl.verticalExtent))
            #expect(abs(a.top - b.top) <= 0.5 && abs(a.bottom - b.bottom) <= 0.5, "\(phase)")
            for y: CGFloat in [2, 15, 30] {
                let (l, r) = (try #require(ltr.rowWidth(atPoint: y)), try #require(rtl.rowWidth(atPoint: y)))
                #expect(abs(l - r) <= 0.5, "\(phase) at \(y) pt: \(l) vs \(r)")
                #expect(abs(ltr.rowCentre(atPoint: y) - rtl.rowCentre(atPoint: y)) <= 0.5, "\(phase) at \(y) pt")
            }
        }
    }

    /// The bubble buds off the trailing wing, which is the left one right to left; the shell's click target is
    /// mirrored with it (`SatelliteMetrics.hitFrame(…layoutDirection:)`).
    @Test func theSatelliteSitsBeyondTheLeftWing() throws {
        let (model, registry) = scene(.compact, satellite: true)
        let probe = try #require(Snapshot.probe(model, registry, layoutDirection: .rightToLeft))
        let canvas = CGRect(origin: .zero, size: model.layout.canvasSize)
        let ltr = SatelliteMetrics.hitFrame(beside: model.geometry, layout: model.layout, in: canvas)
        let rtl = SatelliteMetrics.hitFrame(beside: model.geometry, layout: model.layout, in: canvas, layoutDirection: .rightToLeft)
        #expect(abs((rtl.midX - canvas.midX) + (ltr.midX - canvas.midX)) < 0.001 && rtl.midY == ltr.midY && rtl.size == ltr.size)
        #expect(rtl.maxX < canvas.midX - model.geometry.bodyWidth / 2)
        // The bubble is drawn there: dark down its centre column, and nothing left of it in the band.
        let column = Int(rtl.midX * probe.scale)
        let dark = (0..<probe.height).filter { probe.isDark(x: column, y: $0) }
        let top = try #require(dark.first), bottom = try #require(dark.last)
        #expect(abs(CGFloat(bottom - top + 1) / probe.scale - 24) <= 1)
        #expect(abs(CGFloat(top + bottom + 1) / 2 / probe.scale - rtl.midY) <= 1)
        let band = 0..<Int(model.layout.band * probe.scale)
        let leftmost = try #require(band.compactMap { y in (0..<probe.width).first { probe.isDark(x: $0, y: y) } }.min())
        let bubbleLeft = canvas.midX - (model.layout.satelliteFrame(beside: model.geometry, in: canvas).maxX - canvas.midX)
        #expect(abs(CGFloat(leftmost) / probe.scale - bubbleLeft) <= 1)
    }

    /// Playback progress along the lower rim keeps the timeline's direction (left to right).
    @Test func thePlaybackRimRunsLeftToRight() throws {
        let geometry = NotchLayout(metrics: .reference).compact(.short)
        func image(_ direction: LayoutDirection) throws -> CGImage {
            let rim = ZStack(alignment: .top) {
                NotchShape(geometry).fill(.black)
                LowerRim(geometry: geometry, progress: 0.3, color: Color(red: 1, green: 0, blue: 0))
            }
            .frame(width: 360, height: 60, alignment: .top)
            .background(Color.white)
            .environment(\.layoutDirection, direction)
            let renderer = ImageRenderer(content: rim)
            renderer.scale = 2
            return try #require(renderer.cgImage)
        }
        let ltr = try #require(ShapeProbe(try image(.leftToRight), scale: 2))
        let rtl = try #require(ShapeProbe(try image(.rightToLeft), scale: 2))
        // The red stroke covers the left 30 % of the body in both: compare where red lies, row by row.
        func redColumns(_ probe: ShapeProbe) -> [Int] {
            (0..<probe.height).flatMap { y in (0..<probe.width).filter { x in probe.isRed(x: x, y: y) } }
        }
        let columns = redColumns(rtl)
        #expect(!columns.isEmpty)
        #expect(columns == redColumns(ltr))
        #expect((columns.max() ?? 0) < rtl.width / 2)
    }

    /// A swipe's rubber band moves the wings' content with the fingers (+x = right), not mirrored.
    @Test func compactContentFollowsTheFingers() throws {
        func contentCentre(_ translation: CGFloat) throws -> CGFloat {
            let (model, registry) = scene(.compact, sample: .timer)                // white digits in the trailing wing
            model.gestureTranslation = CGSize(width: translation, height: 0)
            let probe = try #require(Snapshot.probe(model, registry, layoutDirection: .rightToLeft))
            // Bright pixels inside the black shape (between a row's first and last dark pixel): the wings' content.
            var sum = 0.0, count = 0.0
            for y in 0..<Int(model.layout.band * probe.scale) {
                guard let first = (0..<probe.width).first(where: { probe.isDark(x: $0, y: y) }),
                      let last = (0..<probe.width).last(where: { probe.isDark(x: $0, y: y) }) else { continue }
                for x in first...last where probe.luminance(x: x, y: y) > 0.7 { sum += Double(x); count += 1 }
            }
            #expect(count > 0)
            return CGFloat(sum / max(count, 1)) / probe.scale
        }
        let moved = try contentCentre(12) - contentCentre(0)
        #expect(moved > 6, "the wings' content moved \(moved) pt for a +12 pt swipe")
    }
}

private extension ShapeProbe {
    func isRed(x: Int, y: Int) -> Bool {
        let c = color(x: x, y: y)
        return c.r > 0.6 && c.g < 0.35 && c.b < 0.35
    }

    /// The middle of the dark extent of the row `y` points from the top, in points.
    func rowCentre(atPoint y: CGFloat) -> CGFloat {
        let row = min(max(Int(y * scale), 0), height - 1)
        let first = (0..<width).first { isDark(x: $0, y: row) } ?? 0
        let last = (0..<width).last { isDark(x: $0, y: row) } ?? 0
        return CGFloat(first + last + 1) / 2 / scale
    }
}
