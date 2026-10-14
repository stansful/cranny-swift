// CrannyNotchUI/Compact/WingTextMetrics.swift — whether a short text fits a compact wing, by measured width (DESIGN.md
// §9.1, ARCHITECTURE.md §10.20 #26, design ruling E4). A wing gives its content the slot less 12u at the corner and 8u
// at the camera (`CompactSlots`); band text scales with the notch unit and is rounded to whole points, so a word that
// fits at one unit can overflow at another. The fit is therefore measured at every notch unit a display can have,
// never counted in characters. The shell's flash (`NotchControl.flash`) picks its slot with it and draws its symbol
// alone when the label fits no wing.
import AppKit
import CrannyCore
import SwiftUI

/// Measures band text against the compact wings (pure; AppKit text measurement, no views).
public enum WingTextMetrics {
    /// Every notch unit a display can have (`NotchMetrics.unit`: the band height over 32, clamped to 0.8–1.25): each
    /// whole-point band height, and the range in steps of 1/1024 for bands of fractional height, so a fit here holds
    /// at any unit to within 0.1 pt (the font steps up to the next point size between two band heights).
    public static let notchUnits: [CGFloat] = {
        let lowest: CGFloat = 0.8, highest: CGFloat = 1.25, steps: CGFloat = 1024
        let grid = (0...Int(((highest - lowest) * steps).rounded(.down))).map { lowest + CGFloat($0) / steps }
        let bands = (26...40).map { CGFloat($0) / 32 }
        return Array(Set(grid + bands + [highest])).sorted()
    }()

    /// The width a wing of `slot` gives its content at `notchUnit`: the slot less 12u at the corner and 8u at the
    /// camera, as `CompactSlots` lays it out.
    public static func contentWidth(_ slot: SlotWidth, notchUnit: CGFloat) -> CGFloat {
        max(slot.points(unit: notchUnit) - (cornerInset + cameraGap) * notchUnit, 0)
    }

    /// Width of `text` drawn in `style` at `notchUnit` (the standard text size: band styles ignore Text Size), rounded
    /// up to whole points.
    public static func width(of text: String, style: CrannyTextStyle = .compact, notchUnit: CGFloat) -> CGFloat {
        BandFont.width(of: text, style: style, size: style.pointSize(textSize: .standard, notchUnit: notchUnit))
    }

    /// Whether `text` fits one wing of `slot` at every notch unit (`notchUnits`).
    public static func fits(_ text: String, slot: SlotWidth, style: CrannyTextStyle = .compact) -> Bool {
        narrowestSlot(for: text, among: [slot], style: style) != nil
    }

    /// The narrowest of `slots` whose wing holds `text` at every notch unit; nil when none does (then draw the symbol
    /// alone and keep the text for the peek row and VoiceOver). Measures once per point size, not once per unit.
    public static func narrowestSlot(for text: String, among slots: [SlotWidth],
                                     style: CrannyTextStyle = .compact) -> SlotWidth? {
        guard !text.isEmpty else { return slots.min() }
        // The units that draw at each point size; the text is as wide at all of them.
        let unitsBySize = Dictionary(grouping: notchUnits) { style.pointSize(textSize: .standard, notchUnit: $0) }
        let widths = unitsBySize.map { size, units in (BandFont.width(of: text, style: style, size: size), units) }
        return slots.sorted().first { slot in
            widths.allSatisfy { width, units in units.allSatisfy { width <= contentWidth(slot, notchUnit: $0) } }
        }
    }

    /// `CompactSlots`' outer inset, which keeps content off the corner curve (DESIGN.md §9.1).
    static let cornerInset: CGFloat = 12
    /// `CompactSlots`' gap between the content and the camera housing (DESIGN.md §9.1).
    static let cameraGap: CGFloat = 8
}

/// The AppKit twin of `CrannyTextStyle.font` for measuring band text: the same weight and design, monospaced digits
/// when the style has them, the style's tracking and the font's kerning, as SwiftUI draws them.
enum BandFont {
    /// Width of `text` in `style` at `size` points, rounded up to whole points.
    static func width(of text: String, style: CrannyTextStyle, size: CGFloat) -> CGFloat {
        var attributes: [NSAttributedString.Key: Any] = [.font: font(style, size: size)]
        // `.kern` 0 would switch the font's kerning pairs off (SwiftUI keeps them: «Готово» is 2 pt narrower with
        // them); `.tracking` adds space the way `Text.tracking` does and keeps them.
        if style.spec.tracking != 0 { attributes[.tracking] = style.spec.tracking }
        return (text as NSString).size(withAttributes: attributes).width.rounded(.up)
    }

    static func font(_ style: CrannyTextStyle, size: CGFloat) -> NSFont {
        let spec = style.spec
        let base = NSFont.systemFont(ofSize: size, weight: weight(spec.weight))
        var descriptor = base.fontDescriptor
        if spec.design == .rounded, let rounded = descriptor.withDesign(.rounded) { descriptor = rounded }
        if spec.monoDigits {
            descriptor = descriptor.addingAttributes([.featureSettings: [[
                NSFontDescriptor.FeatureKey.typeIdentifier: kNumberSpacingType,
                NSFontDescriptor.FeatureKey.selectorIdentifier: kMonospacedNumbersSelector,
            ]]])
        }
        return NSFont(descriptor: descriptor, size: size) ?? base
    }

    private static func weight(_ weight: Font.Weight) -> NSFont.Weight {
        switch weight {
        case .ultraLight: .ultraLight
        case .thin: .thin
        case .light: .light
        case .medium: .medium
        case .semibold: .semibold
        case .bold: .bold
        case .heavy: .heavy
        case .black: .black
        default: .regular
        }
    }
}
