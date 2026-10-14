// Right-to-left rules (CrannyCore/DesignSystem/RightToLeft.swift, ARCHITECTURE.md §8.7): what SwiftUI mirrors in a
// right-to-left layout, what Cranny keeps left to right, and the conversions between physical input and the layout.
import AppKit
import Foundation
import SwiftUI
import Testing
@testable import CrannyCore

@Suite("Right to left") struct RightToLeftTests {
    @Test func physicalTravelAlongTheLayout() {
        #expect(LayoutDirection.leftToRight.alongLayout(12) == 12)
        #expect(LayoutDirection.rightToLeft.alongLayout(12) == -12)
        #expect(LayoutDirection.rightToLeft.alongLayout(CGSize(width: 5, height: 7)) == CGSize(width: -5, height: 7))
        // Its own inverse: a layout distance back to the screen.
        #expect(LayoutDirection.rightToLeft.alongLayout(LayoutDirection.rightToLeft.alongLayout(3)) == 3)
    }

    /// A press 30 pt from the left of a 120-pt bar: a quarter from the left edge, where the bar fills from in
    /// English; three quarters from the right edge, where it fills from in Arabic.
    @Test func fractionCountsFromTheLeadingEdge() {
        #expect(LayoutDirection.leftToRight.fraction(atPhysicalX: 30, width: 120) == 0.25)
        #expect(LayoutDirection.rightToLeft.fraction(atPhysicalX: 30, width: 120) == 0.75)
        #expect(LayoutDirection.rightToLeft.fraction(atPhysicalX: -8, width: 120) == 1)
        #expect(LayoutDirection.leftToRight.fraction(atPhysicalX: 500, width: 120) == 1)
        #expect(LayoutDirection.leftToRight.fraction(atPhysicalX: 5, width: 0) == 1)          // never divides by 0
    }

    /// ← and → move toward the side they point at: back and forward in English, forward and back in Arabic.
    @Test func arrowsAndMoveCommandsGoTheWayTheyPoint() {
        #expect(LayoutDirection.leftToRight.step(for: .leftArrow) == -1)
        #expect(LayoutDirection.leftToRight.step(for: .rightArrow) == 1)
        #expect(LayoutDirection.rightToLeft.step(for: .leftArrow) == 1)
        #expect(LayoutDirection.rightToLeft.step(for: .rightArrow) == -1)
        #expect(LayoutDirection.rightToLeft.step(for: .upArrow) == nil)
        #expect(LayoutDirection.leftToRight.step(physical: -1) == -1)
        #expect(LayoutDirection.rightToLeft.step(physical: -1) == 1)
    }

    @Test func isolationWrapsOnceAndLeavesEmptyTextAlone() {
        #expect("⌃⌥N".crannyIsolated == "\u{2068}⌃⌥N\u{2069}")
        #expect("⌃⌥N".crannyIsolated.crannyIsolated == "⌃⌥N".crannyIsolated)
        #expect("".crannyIsolated.isEmpty)
        // Invisible: the same glyphs, the same width.
        let font = NSFont.systemFont(ofSize: 13)
        func width(_ s: String) -> CGFloat { (s as NSString).size(withAttributes: [.font: font]).width }
        #expect(abs(width("Anna’s iPhone".crannyIsolated) - width("Anna’s iPhone")) < 0.01)
    }

    @Test func aTextReadsInTheDirectionOfItsFirstLetter() {
        #expect(BidiIsolation.direction(of: "Midnight Window") == .leftToRight)
        #expect(BidiIsolation.direction(of: "مراجعة التصميم") == .rightToLeft)
        #expect(BidiIsolation.direction(of: "שלום") == .rightToLeft)
        #expect(BidiIsolation.direction(of: "12:30 – Anna") == .leftToRight)       // digits and signs are weak
        #expect(BidiIsolation.direction(of: "١٢ مارس") == .rightToLeft)             // so are Arabic-Indic digits
        #expect(BidiIsolation.direction(of: "“東京”") == .leftToRight)
        #expect(BidiIsolation.direction(of: "+3") == nil)
        #expect(BidiIsolation.direction(of: "") == nil)
    }
}

/// Rendered checks: the same view drawn left to right and right to left (ImageRenderer, 2×, over white).
@MainActor @Suite("Right to left, rendered") struct RightToLeftRenderTests {
    private func render(_ view: some View, _ direction: LayoutDirection, size: CGSize) throws -> RenderedPixels {
        let content = view
            .frame(width: size.width, height: size.height)
            .background(Color.white)
            .environment(\.layoutDirection, direction)
            .crannyThemeRoot(CrannyTheme())
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        let image = try #require(renderer.cgImage)
        return try #require(RenderedPixels(image))
    }

    /// A ring fills clockwise from 12 o'clock in every language: SwiftUI mirrors a `rotationEffect`, so a mirrored
    /// quarter would start at 6 o'clock and lie bottom-left.
    @Test func progressRingFillsClockwiseFromTwelveInBothDirections() throws {
        let ring = ProgressRing(progress: 0.25, color: Color(red: 1, green: 0, blue: 0), lineWidth: 6)
        let size = CGSize(width: 60, height: 60)
        let ltr = try render(ring, .leftToRight, size: size)
        let rtl = try render(ring, .rightToLeft, size: size)
        #expect(rtl.differing(from: ltr) < 20)
        let arc = try #require(rtl.centroid(of: { $0.r > 0.8 && $0.g < 0.4 }))
        #expect(arc.x > 30 && arc.y < 30, "the quarter lies top-right: \(arc)")
    }

    /// Content that follows the fingers moves right for a positive translation in both directions; a plain
    /// `offset(x:)` would go left right to left (the rule `crannyPhysicalOffset` exists for).
    @Test func physicalOffsetFollowsTheFingers() throws {
        let size = CGSize(width: 100, height: 20)
        func dot(physical: Bool) -> some View {
            ZStack {
                if physical {
                    Color.red.frame(width: 10, height: 10).crannyPhysicalOffset(x: 30)
                } else {
                    Color.red.frame(width: 10, height: 10).offset(x: 30)
                }
            }
        }
        for direction in [LayoutDirection.leftToRight, .rightToLeft] {
            let centre = try #require(try render(dot(physical: true), direction, size: size).centroid(of: \.isRed))
            #expect(abs(centre.x - 80) < 1, "\(direction): \(centre)")
        }
        let mirrored = try #require(try render(dot(physical: false), .rightToLeft, size: size).centroid(of: \.isRed))
        #expect(abs(mirrored.x - 20) < 1, "SwiftUI mirrors offset(x:) right to left: \(mirrored)")
    }

    /// `crannyLeftToRight()` keeps a row's order inside a mirrored layout (time-based media: ⏮ before ⏭).
    @Test func leftToRightContentKeepsItsOrder() throws {
        let row = HStack(spacing: 0) { Color.red; Color.blue }.crannyLeftToRight()
        let size = CGSize(width: 80, height: 10)
        let ltr = try render(row, .leftToRight, size: size)
        let rtl = try render(row, .rightToLeft, size: size)
        #expect(rtl.differing(from: ltr) == 0)
        #expect(try #require(rtl.centroid(of: \.isRed)).x < 40)
        // Without it, the row is mirrored.
        let mirrored = try render(HStack(spacing: 0) { Color.red; Color.blue }, .rightToLeft, size: size)
        #expect(try #require(mirrored.centroid(of: \.isRed)).x > 40)
    }

    /// A level bar (HUD, sliders) does mirror: right to left it fills from the right edge, like the system's.
    @Test func levelBarFillsFromTheLeadingEdge() throws {
        let bar = LevelBar(value: 0.25, tint: Color(red: 1, green: 0, blue: 0), thickness: 8)
        let size = CGSize(width: 120, height: 8)
        let ltr = try #require(try render(bar, .leftToRight, size: size).centroid(of: \.isRed))
        let rtl = try #require(try render(bar, .rightToLeft, size: size).centroid(of: \.isRed))
        #expect(ltr.x < 30 && rtl.x > 90, "ltr \(ltr), rtl \(rtl)")
    }
}

/// An RGBA copy of a rendered image, compared pixel by pixel; coordinates in points (2×), y down.
struct RenderedPixels {
    struct Pixel { let r, g, b, a: Double; var isRed: Bool { r > 0.8 && g < 0.3 && b < 0.3 } }
    let width: Int, height: Int
    private let bytes: [UInt8]

    init?(_ image: CGImage) {
        width = image.width; height = image.height
        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = buffer.withUnsafeMutableBytes { raw -> Bool in
            guard let space = CGColorSpace(name: CGColorSpace.sRGB),
                  let ctx = CGContext(data: raw.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
                                      bytesPerRow: image.width * 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return true
        }
        guard drawn else { return nil }
        bytes = buffer
    }

    func pixel(x: Int, y: Int) -> Pixel {
        let i = (y * width + x) * 4
        return Pixel(r: Double(bytes[i]) / 255, g: Double(bytes[i + 1]) / 255, b: Double(bytes[i + 2]) / 255,
                     a: Double(bytes[i + 3]) / 255)
    }

    /// Pixels that differ visibly from `other` (antialiasing at a direction flip may move an edge pixel).
    func differing(from other: RenderedPixels) -> Int {
        guard width == other.width, height == other.height else { return .max }
        var count = 0
        for y in 0..<height { for x in 0..<width {
            let a = pixel(x: x, y: y), b = other.pixel(x: x, y: y)
            if abs(a.r - b.r) > 0.19 || abs(a.g - b.g) > 0.19 || abs(a.b - b.b) > 0.19 { count += 1 }
        } }
        return count
    }

    /// The centre of the pixels that match, in points; nil when none does.
    func centroid(of matches: (Pixel) -> Bool) -> CGPoint? {
        var sx = 0.0, sy = 0.0, n = 0.0
        for y in 0..<height { for x in 0..<width where matches(pixel(x: x, y: y)) { sx += Double(x); sy += Double(y); n += 1 } }
        guard n > 0 else { return nil }
        return CGPoint(x: (sx / n + 0.5) / 2, y: (sy / n + 0.5) / 2)
    }
}
