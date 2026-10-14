// ‹ › point the way the days run (ARCHITECTURE.md §8.7): right to left the previous day is the right-hand button and
// its chevron points right, the next day the left-hand one pointing left, so the pager draws "‹ ›" as in English.
// With `chevron.left` / `chevron.right` the mirrored row read "› ‹".
import AppKit
import CrannyCore
import Foundation
import SwiftUI
import Testing
@testable import CrannyCalendar

@MainActor @Suite("Day pager right to left") struct DayPagerDirectionTests {
    private func render(_ model: CalendarModel, _ direction: LayoutDirection) throws -> (pixels: [UInt8], width: Int, height: Int) {
        let renderer = ImageRenderer(content: DayPager(model: model)
            .frame(width: 80, height: 20)
            .background(Color.black)                                        // the Nook's: white glyphs
            .environment(\.layoutDirection, direction)
            .crannyThemeRoot(CrannyTheme()))
        renderer.scale = 2
        let image = try #require(renderer.cgImage)
        var pixels = [UInt8](repeating: 0, count: image.width * image.height)
        let drawn = pixels.withUnsafeMutableBytes { raw -> Bool in
            guard let ctx = CGContext(data: raw.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
                                      bytesPerRow: image.width, space: CGColorSpaceCreateDeviceGray(),
                                      bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return true
        }
        #expect(drawn)
        return (pixels, image.width, image.height)
    }

    @Test func thePagerLooksTheSameRightToLeft() async throws {
        let services = CrannyServices.preview()
        services.settings[CalendarSettings.daysBehind] = 1                      // both buttons enabled
        services.settings[CalendarSettings.daysAhead] = 1
        let model = await makeModel([], time: TestTime(T.date()), services: services)
        let ltr = try render(model, .leftToRight), rtl = try render(model, .rightToLeft)
        #expect(ltr.width == rtl.width && ltr.height == rtl.height)
        // Every inked pixel of one has ink in the other within 3 px on its row (the glyphs may land a pixel or two
        // apart); opposite chevrons do not overlap like that.
        func unmatched(_ a: [UInt8], _ b: [UInt8], width: Int, height: Int) -> (missing: Int, ink: Int) {
            var missing = 0, ink = 0
            for y in 0..<height {
                for x in 0..<width where a[y * width + x] > 128 {
                    ink += 1
                    let near = (max(x - 3, 0)...min(x + 3, width - 1)).contains { b[y * width + $0] > 128 }
                    if !near { missing += 1 }
                }
            }
            return (missing, ink)
        }
        for (a, b) in [(rtl.pixels, ltr.pixels), (ltr.pixels, rtl.pixels)] {
            let result = unmatched(a, b, width: ltr.width, height: ltr.height)
            #expect(result.ink > 20, "the chevrons are drawn")
            #expect(result.missing * 20 < result.ink, "\(result.missing) of \(result.ink) inked pixels have no counterpart")
        }
    }
}
