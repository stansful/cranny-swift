// CrannyCore/DesignSystem/Typography.swift
// SF Pro for words, SF Pro Rounded with monospaced digits for live numbers, SF Mono for code.
// macOS has no Dynamic Type for third-party UI, so Cranny ships its own Text Size setting.
import SwiftUI

/// Settings ▸ Appearance ▸ Text size. Scales every Nook/peek style AND grows the grid cell.
public nonisolated enum CrannyTextSize: String, CaseIterable, Codable, Sendable {
    case small, standard, large, extraLarge
    public var scale: CGFloat {
        switch self {
        case .small: 0.92
        case .standard: 1
        case .large: 1.12
        case .extraLarge: 1.24
        }
    }
}

public nonisolated enum CrannyTextStyle: String, CaseIterable, Sendable {
    case display       // 28 semibold rounded, mono digits — focused timer, big peek numbers
    case numeral       // 22 semibold rounded, mono digits — timer ring, calendar date, battery % in peek
    case title         // 15 semibold — track title, event title, peek primary line
    case headline      // 13 semibold — widget headers, tabs, note title
    case body          // 13 regular — notes, to-dos (minimum size for sentences)
    case callout       // 12 regular — artist, secondary lines
    case caption       // 11 medium, mono digits — times, metadata, file names, chips
    case eyebrow       // 11 semibold, sentence case — section labels ("Up next")
    case micro         // 10 semibold rounded, UPPERCASE — weekday "TUE", badges (≤ 4 characters)
    case compact       // 13 semibold rounded, mono digits — values in the band ("4:59", "82%")
    case compactLabel  // 12 medium rounded, mono digits — short labels in the band ("in 4m")
    case code          // 12 regular SF Mono — Notes code mode

    public nonisolated enum Scaling: Sendable { case textSize, notchUnit }

    public nonisolated struct Spec: Equatable, Sendable {
        public let size: CGFloat
        public let weight: Font.Weight
        public let design: Font.Design
        public let lineHeight: CGFloat
        public let tracking: CGFloat
        public let monoDigits: Bool
        public let uppercase: Bool
    }

    public var spec: Spec {
        switch self {
        case .display:      Spec(size: 28, weight: .semibold, design: .rounded,    lineHeight: 32, tracking: -0.3, monoDigits: true,  uppercase: false)
        case .numeral:      Spec(size: 22, weight: .semibold, design: .rounded,    lineHeight: 26, tracking: -0.2, monoDigits: true,  uppercase: false)
        case .title:        Spec(size: 15, weight: .semibold, design: .default,    lineHeight: 20, tracking: -0.1, monoDigits: false, uppercase: false)
        case .headline:     Spec(size: 13, weight: .semibold, design: .default,    lineHeight: 16, tracking: 0,    monoDigits: false, uppercase: false)
        case .body:         Spec(size: 13, weight: .regular,  design: .default,    lineHeight: 17, tracking: 0,    monoDigits: false, uppercase: false)
        case .callout:      Spec(size: 12, weight: .regular,  design: .default,    lineHeight: 15, tracking: 0,    monoDigits: false, uppercase: false)
        case .caption:      Spec(size: 11, weight: .medium,   design: .default,    lineHeight: 14, tracking: 0.1,  monoDigits: true,  uppercase: false)
        case .eyebrow:      Spec(size: 11, weight: .semibold, design: .default,    lineHeight: 13, tracking: 0.2,  monoDigits: false, uppercase: false)
        case .micro:        Spec(size: 10, weight: .semibold, design: .rounded,    lineHeight: 12, tracking: 0.6,  monoDigits: true,  uppercase: true)
        case .compact:      Spec(size: 13, weight: .semibold, design: .rounded,    lineHeight: 16, tracking: 0,    monoDigits: true,  uppercase: false)
        case .compactLabel: Spec(size: 12, weight: .medium,   design: .rounded,    lineHeight: 14, tracking: 0,    monoDigits: true,  uppercase: false)
        case .code:         Spec(size: 12, weight: .regular,  design: .monospaced, lineHeight: 16, tracking: 0,    monoDigits: true,  uppercase: false)
        }
    }

    /// Band styles must fit the hardware row, so they scale with the notch unit (display
    /// scaling), never with Text Size. Everything else follows Text Size.
    public var scaling: Scaling { self == .compact || self == .compactLabel ? .notchUnit : .textSize }

    public func pointSize(textSize: CrannyTextSize, notchUnit: CGFloat) -> CGFloat {
        let k = scaling == .notchUnit ? notchUnit : textSize.scale
        return max((spec.size * k).rounded(), 10)          // nothing is ever smaller than 10 pt
    }

    public func font(textSize: CrannyTextSize = .standard, notchUnit: CGFloat = 1) -> Font {
        let s = spec
        let f = Font.system(size: pointSize(textSize: textSize, notchUnit: notchUnit), weight: s.weight, design: s.design)
        return s.monoDigits ? f.monospacedDigit() : f
    }
}

public struct CrannyFontModifier: ViewModifier {
    @Environment(\.cranny) private var theme
    public let style: CrannyTextStyle
    public init(_ style: CrannyTextStyle) { self.style = style }

    public func body(content: Content) -> some View {
        let s = style.spec
        let size = style.pointSize(textSize: theme.textSize, notchUnit: theme.notchUnit)
        let lineHeight = s.lineHeight * size / s.size
        content
            .font(style.font(textSize: theme.textSize, notchUnit: theme.notchUnit))
            .tracking(s.tracking)
            .lineSpacing(max(0, lineHeight - size * 1.2))
            .textCase(s.uppercase ? .uppercase : nil)
    }
}

public extension View {
    /// `Text(track.title).crannyFont(.title)` — font, tracking, line height and case in one call.
    func crannyFont(_ style: CrannyTextStyle) -> some View { modifier(CrannyFontModifier(style)) }
}

// MARK: - SF Symbol glyph styles (DESIGN.md §14.1 "Rendering")

/// How an SF Symbol is drawn where it is not inside a button style (which sizes its own glyph) or next to text
/// (which takes the text's `crannyFont`). Band glyphs scale with the notch unit, like the band text styles; Nook
/// glyphs follow Text Size.
public nonisolated enum CrannySymbolStyle: String, CaseIterable, Sendable {
    case band          // 13 semibold × notch unit — one glyph in a compact wing (now playing, charging, flash)
    case nook          // 13 medium × text size — a glyph inside the open Nook
    case peekVisual    // 18 semibold × text size — a glyph filling the 40-pt visual of a peek row
    case widgetState   // 20 medium × text size — the glyph of an empty / permission / error state (§6.8)
    case dropZone      // 22 medium × text size — the glyph of a drop zone (Tray, AirDrop, pipelines)

    /// Point size before scaling, and weight.
    public var spec: (size: CGFloat, weight: Font.Weight) {
        switch self {
        case .band: (13, .semibold)
        case .nook: (13, .medium)
        case .peekVisual: (18, .semibold)
        case .widgetState: (20, .medium)
        case .dropZone: (22, .medium)
        }
    }

    /// `.band` scales with the notch unit (the band is hardware height); everything else with Text Size.
    public var scaling: CrannyTextStyle.Scaling { self == .band ? .notchUnit : .textSize }

    /// The scaled point size (never below 10 pt).
    public func pointSize(textSize: CrannyTextSize, notchUnit: CGFloat) -> CGFloat {
        let k = scaling == .notchUnit ? notchUnit : textSize.scale
        return max((spec.size * k).rounded(), 10)
    }

    /// The symbol font at that size.
    public func font(textSize: CrannyTextSize = .standard, notchUnit: CGFloat = 1) -> Font {
        .system(size: pointSize(textSize: textSize, notchUnit: notchUnit), weight: spec.weight)
    }
}

public struct CrannySymbolModifier: ViewModifier {
    @Environment(\.cranny) private var theme
    public let style: CrannySymbolStyle
    public init(_ style: CrannySymbolStyle) { self.style = style }
    public func body(content: Content) -> some View {
        content.font(style.font(textSize: theme.textSize, notchUnit: theme.notchUnit))
    }
}

public extension View {
    /// `Image(systemName: "bolt.fill").crannySymbol(.band)` — the glyph's size and weight from the theme.
    func crannySymbol(_ style: CrannySymbolStyle) -> some View { modifier(CrannySymbolModifier(style)) }
}
