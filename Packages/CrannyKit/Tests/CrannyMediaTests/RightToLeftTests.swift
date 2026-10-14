// Time-based media keeps its direction in a right-to-left language (Apple HIG, Right to left ▸ Controls; ARCHITECTURE.md
// §8.7): ⏮ ⏯ ⏭, the scrubber and its elapsed / remaining labels are drawn exactly as in English, while the widget
// around them is mirrored (artwork on the right).
import AppKit
import CrannyCore
import Foundation
import SwiftUI
import Testing
@testable import CrannyMedia

@MainActor @Suite("Media right to left") struct MediaRightToLeftTests {
    /// RGBA bytes of `view` over black at 2×.
    private func pixels(_ view: some View, _ direction: LayoutDirection, size: CGSize) throws -> [UInt8] {
        let content = view
            .frame(width: size.width, height: size.height)
            .background(Color.black)
            .environment(\.layoutDirection, direction)
            .crannyThemeRoot(CrannyTheme())
        let renderer = ImageRenderer(content: content)
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
        #expect(drawn)
        return bytes
    }

    /// Pixels that differ visibly between two renders of the same size (antialiasing at a direction flip may move
    /// an edge pixel; a mirrored control moves hundreds).
    private func differing(_ a: [UInt8], _ b: [UInt8]) -> Int {
        guard a.count == b.count else { return .max }
        return stride(from: 0, to: a.count, by: 4).count { i in (0..<3).contains { abs(Int(a[i + $0]) - Int(b[i + $0])) > 48 } }
    }

    @Test func transportControlsKeepTheirOrder() throws {
        let service = SampleMedia.previewService(playing: false)
        for (prominent, spacing) in [(true, Space.m), (false, CGFloat(0))] {
            let controls = TransportControls(service: service, prominentPlayPause: prominent, showsModes: prominent, spacing: spacing)
            let size = CGSize(width: 220, height: 40)
            #expect(differing(try pixels(controls, .rightToLeft, size: size), try pixels(controls, .leftToRight, size: size)) < 20)
        }
    }

    /// A paused track (the position does not move between the two renders): bar, "1:27" left, "−2:08" right.
    @Test func scrubberAndTimeLabelsKeepTheirDirection() throws {
        let service = SampleMedia.previewService(playing: false)
        for style in [MediaProgress.Style.stacked, .inline, .hairline] {
            let progress = MediaProgress(service: service, style: style)
            let size = CGSize(width: 220, height: 28)
            #expect(differing(try pixels(progress, .rightToLeft, size: size), try pixels(progress, .leftToRight, size: size)) < 20, "\(style)")
        }
    }

    /// "−2:11" carries its own direction: without a letter, an Arabic or Hebrew app would put the minus after the digits.
    @Test func theTimeLeftReadsLeftToRightOnItsOwn() {
        let label = MediaStrings.remaining(131)
        #expect(label.first == BidiIsolation.leftToRightMark)
        #expect(label.dropFirst() == "\u{2212}" + MediaStrings.clock(131))
    }

    /// The widget itself is mirrored: right to left it is not the English drawing.
    @Test func theWidgetAroundThemIsMirrored() throws {
        let service = SampleMedia.previewService(playing: false)
        let theme = CrannyTheme(), cells = 5
        let pad = theme.grid.density.cardPadding
        let widget = MediaWidgetView(service: service, context: WidgetContext(
            cells: cells, contentSize: CGSize(width: theme.grid.width(cells: cells) - 2 * pad, height: theme.grid.height - 2 * pad)),
            haptics: nil, settings: service.settings)
            .crannyCard(cells: cells)
        let size = CGSize(width: theme.grid.width(cells: cells), height: theme.grid.height)
        #expect(differing(try pixels(widget, .rightToLeft, size: size), try pixels(widget, .leftToRight, size: size)) > 1000)
    }
}
