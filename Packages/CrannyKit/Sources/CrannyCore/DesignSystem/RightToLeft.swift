// CrannyCore/DesignSystem/RightToLeft.swift — the right-to-left rules every module follows (ARCHITECTURE.md §8.7
// "Right-to-left", DESIGN.md §17). In a right-to-left language (Arabic, Hebrew) AppKit hands every hosting view a
// right-to-left layout and SwiftUI mirrors it: stacks run from the right, `.leading` is the right edge, `offset(x:)`
// and `position(x:)` count from the right, custom `Shape`s are drawn mirrored and so is a `rotationEffect`. Input is
// NOT mirrored: a gesture's location and translation, scroll deltas and every AppKit coordinate stay physical (left
// to right), so code that turns a pointer or finger position into a layout position converts it here.
//
// Kept left to right on purpose (Apple HIG, Right to left ▸ Controls): time-based media — transport controls,
// playback scrubbers and their time labels, the playback rim — and clock-like rings, which fill clockwise from
// 12 o'clock in every language. The notch itself is physical: its shape is centred on the camera and symmetric.
import Foundation
import SwiftUI

public extension LayoutDirection {
    /// A physical horizontal distance (pointer or finger travel, a gesture's translation, left to right) as a
    /// distance along this layout (leading to trailing), and back again: the same number left to right, negated
    /// right to left.
    nonisolated func alongLayout(_ physical: CGFloat) -> CGFloat { self == .rightToLeft ? -physical : physical }

    /// `alongLayout(_:)` for a 2-D translation: only the horizontal part depends on the direction.
    nonisolated func alongLayout(_ physical: CGSize) -> CGSize {
        CGSize(width: alongLayout(physical.width), height: physical.height)
    }

    /// The fraction (0…1) of a `width`-wide control at physical `x` (a gesture's location: 0 = the left edge),
    /// measured from the layout's leading edge, where a level bar starts filling.
    nonisolated func fraction(atPhysicalX x: CGFloat, width: CGFloat) -> Double {
        let f = Double(min(max(x / max(width, 1), 0), 1))
        return self == .rightToLeft ? 1 - f : f
    }

    /// The step along a mirrored row of ← (`-1` left to right) or → (`+1`), so the arrow keys always move toward the
    /// side they point at: in a right-to-left row → goes back to the previous item. Nil for any other key.
    nonisolated func step(for key: KeyEquivalent) -> Int? {
        let physical: Int
        switch key {
        case .leftArrow: physical = -1
        case .rightArrow: physical = 1
        default: return nil
        }
        return self == .rightToLeft ? -physical : physical
    }

    /// The step of a "Move Left" (`physical` −1) or "Move Right" (+1) command along this layout's order.
    nonisolated func step(physical: Int) -> Int { self == .rightToLeft ? -physical : physical }
}

public extension View {
    /// Moves the view `x` points toward the right edge of the screen and `y` points down, in every layout direction:
    /// for content that follows the pointer or the fingers (a swipe's rubber band, a dragged card), whose
    /// translation is physical. A plain `offset(x:)` is mirrored in a right-to-left layout.
    func crannyPhysicalOffset(x: CGFloat = 0, y: CGFloat = 0) -> some View {
        modifier(PhysicalOffset(x: x, y: y))
    }

    /// `crannyPhysicalOffset(x:y:)` for a translation.
    func crannyPhysicalOffset(_ translation: CGSize) -> some View {
        modifier(PhysicalOffset(x: translation.width, y: translation.height))
    }

    /// Lays the content out left to right in every language (Apple HIG, Right to left ▸ Controls): time-based media
    /// (⏮ ⏯ ⏭, a playback scrubber with its elapsed and remaining time, the playback rim) and clock-like rings.
    /// Text inside still reads in its own direction; only the order, the alignment and the fill stay put.
    func crannyLeftToRight() -> some View { environment(\.layoutDirection, .leftToRight) }
}

private struct PhysicalOffset: ViewModifier {
    @Environment(\.layoutDirection) private var direction
    let x: CGFloat, y: CGFloat

    func body(content: Content) -> some View {
        content.offset(x: direction.alongLayout(x), y: y)
    }
}

/// Unicode bidirectional isolation for text that is put into a sentence: a name (an app, a file, a note, a device,
/// a display), a key combination or a version. Between FIRST STRONG ISOLATE and POP DIRECTIONAL ISOLATE
/// (Unicode TR9) the inserted text takes its direction from its own first letter and cannot reorder the sentence
/// around it: "⌃⌥N" stays "⌃⌥N" inside an Arabic sentence, and a Hebrew file name inside an English one keeps its
/// quotes in place. Both marks are invisible and take no width; VoiceOver skips them.
public nonisolated enum BidiIsolation {
    /// U+2068 FIRST STRONG ISOLATE.
    public static let firstStrongIsolate: Character = "\u{2068}"
    /// U+2069 POP DIRECTIONAL ISOLATE.
    public static let popDirectionalIsolate: Character = "\u{2069}"
    /// U+200E LEFT-TO-RIGHT MARK: opening a text that has no letters ("−2:11"), it makes the paragraph left to right,
    /// which otherwise follows the app's language (right to left in Arabic and Hebrew).
    public static let leftToRightMark: Character = "\u{200E}"

    /// `text` isolated (empty text stays empty; text that is already isolated is returned as it is).
    public static func isolate(_ text: String) -> String {
        guard !text.isEmpty, text.first != firstStrongIsolate else { return text }
        return String(firstStrongIsolate) + text + String(popDirectionalIsolate)
    }

    /// The direction `text` reads in on its own: that of its first letter (Unicode's "first strong" rule, the one
    /// `Text` uses for a paragraph), or nil when it has none ("12:30", "+3", "—"); such a text then follows the app's
    /// language.
    /// Hebrew, Arabic and the other right-to-left scripts read right to left; any other letter left to right.
    public static func direction(of text: String) -> LayoutDirection? {
        for scalar in text.unicodeScalars where scalar.properties.isAlphabetic {      // digits, signs and punctuation are weak
            return isRightToLeft(scalar) ? .rightToLeft : .leftToRight
        }
        return nil
    }

    /// The blocks of the right-to-left scripts (Hebrew, Arabic, Syriac, Thaana, N'Ko, Samaritan, Mandaic and their
    /// presentation forms, and the historic ones above U+10800).
    private static func isRightToLeft(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x0590...0x08FF, 0xFB1D...0xFDFF, 0xFE70...0xFEFF, 0x10800...0x10FFF, 0x1E800...0x1EFFF: true
        default: false
        }
    }
}

public extension String {
    /// This text as one bidirectional isolate, for putting into a localized sentence (`BidiIsolation`).
    nonisolated var crannyIsolated: String { BidiIsolation.isolate(self) }
}
