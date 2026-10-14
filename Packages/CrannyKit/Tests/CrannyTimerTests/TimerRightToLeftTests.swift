// The timer's ring is a clock: it runs clockwise from 12 o'clock in every language (Apple HIG, Right to left: controls
// for time-based media keep their direction; ARCHITECTURE.md §8.7). SwiftUI mirrors a rotation right to left, which
// once started the arc at 6 o'clock.
import AppKit
import CrannyCore
import Foundation
import SwiftUI
import Testing
@testable import CrannyTimer

@MainActor @Suite("Timer right to left") struct TimerRightToLeftTests {
    /// RGBA bytes of the ring over black at 2× (80 × 80 pt).
    private func pixels(_ view: some View, _ direction: LayoutDirection) throws -> [UInt8] {
        let renderer = ImageRenderer(content: view
            .frame(width: 80, height: 80)
            .background(Color.black)
            .environment(\.layoutDirection, direction)
            .crannyThemeRoot(CrannyTheme()))
        renderer.scale = 2
        let image = try #require(renderer.cgImage)
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let drawn = bytes.withUnsafeMutableBytes { raw -> Bool in
            guard let ctx = CGContext(data: raw.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
                                      bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return true
        }
        #expect(drawn && image.width == 160)
        return bytes
    }

    /// Paused, so the arc does not move between the renders: a third of the time left, from 12 to 4 o'clock. The two
    /// directions draw the same pixels (bar antialiasing at the flip, a few edge pixels at most); a mirrored ring
    /// would cover 6 to 10 o'clock instead.
    @Test func ringIsTheSameRightToLeft() throws {
        let state = TimerModel.sample(.paused(left: 100, total: 300)).state
        for lineWidth in [StrokeWidth.ring, StrokeWidth.ringCompact] {
            let ring = TimerRing(state: state, diameter: 64, lineWidth: lineWidth)
            let ltr = try pixels(ring, .leftToRight), rtl = try pixels(ring, .rightToLeft)
            var differing = 0, warm = 0, sumX = 0, sumY = 0
            for i in stride(from: 0, to: rtl.count, by: 4) {
                if (0..<3).contains(where: { abs(Int(ltr[i + $0]) - Int(rtl[i + $0])) > 48 }) { differing += 1 }
                if rtl[i] > 160 && rtl[i + 2] < 80 {                       // the orange arc (warning colour)
                    warm += 1; sumX += (i / 4) % 160; sumY += (i / 4) / 160
                }
            }
            #expect(differing < 20, "\(lineWidth): \(differing) pixels differ")
            #expect(warm > 0 && sumX / max(warm, 1) > 80 && sumY / max(warm, 1) < 80, "the arc lies right of 12 o'clock")
        }
    }
}
