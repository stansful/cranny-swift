// CrannyCore/DesignSystem/Color.swift
// Colour tokens. The notch surfaces are ALWAYS dark (they extend the black hardware
// notch). Settings, onboarding and menus are ordinary windows and use system colours.
import SwiftUI
import AppKit

// MARK: - RGB: palette math (sRGB 0…1), animatable

/// sRGB triple used for contrast math, accents and ambient palettes. It is
/// `VectorArithmetic`, so palettes cross-fade inside Canvas/MeshGradient effects.
public nonisolated struct RGB: Hashable, Sendable, VectorArithmetic {
    public var r: Double, g: Double, b: Double

    public init(_ r: Double, _ g: Double, _ b: Double) { self.r = r; self.g = g; self.b = b }
    public init(white w: Double) { self.init(w, w, w) }
    public init(hex: UInt32) {
        self.init(Double((hex >> 16) & 0xFF) / 255, Double((hex >> 8) & 0xFF) / 255, Double(hex & 0xFF) / 255)
    }

    public var color: Color { color(1) }
    public func color(_ opacity: Double) -> Color {
        Color(.sRGB, red: Self.clamp(r), green: Self.clamp(g), blue: Self.clamp(b), opacity: opacity)
    }
    public var nsColor: NSColor {
        NSColor(srgbRed: Self.clamp(r), green: Self.clamp(g), blue: Self.clamp(b), alpha: 1)
    }
    private static func clamp(_ v: Double) -> Double { min(max(v, 0), 1) }

    // VectorArithmetic
    public static var zero: RGB { RGB(0, 0, 0) }
    public static func + (a: RGB, b: RGB) -> RGB { RGB(a.r + b.r, a.g + b.g, a.b + b.b) }
    public static func - (a: RGB, b: RGB) -> RGB { RGB(a.r - b.r, a.g - b.g, a.b - b.b) }
    public mutating func scale(by k: Double) { r *= k; g *= k; b *= k }
    public var magnitudeSquared: Double { r * r + g * g + b * b }

    // WCAG 2.x
    public var luminance: Double {
        func lin(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(Self.clamp(r)) + 0.7152 * lin(Self.clamp(g)) + 0.0722 * lin(Self.clamp(b))
    }
    /// Contrast ratio 1…21.
    public func contrast(with o: RGB) -> Double {
        let a = luminance, b = o.luminance
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }
    /// `self` drawn at `alpha` over `background` (sRGB "over"; matches how the tokens composite).
    public func over(_ background: RGB, alpha: Double) -> RGB {
        RGB(r * alpha + background.r * (1 - alpha), g * alpha + background.g * (1 - alpha), b * alpha + background.b * (1 - alpha))
    }

    public var hsb: (h: Double, s: Double, v: Double) {
        let mx = max(r, g, b), mn = min(r, g, b), d = mx - mn
        var h = 0.0
        if d > 0 {
            if mx == r { h = ((g - b) / d).truncatingRemainder(dividingBy: 6) }
            else if mx == g { h = (b - r) / d + 2 }
            else { h = (r - g) / d + 4 }
            h /= 6
            if h < 0 { h += 1 }
        }
        return (h, mx == 0 ? 0 : d / mx, mx)
    }
    public init(h: Double, s: Double, v: Double) {
        let i = floor(h * 6), f = h * 6 - i
        let p = v * (1 - s), q = v * (1 - f * s), t = v * (1 - (1 - f) * s)
        switch Int(i) % 6 {
        case 0: self.init(v, t, p)
        case 1: self.init(q, v, p)
        case 2: self.init(p, v, t)
        case 3: self.init(p, q, v)
        case 4: self.init(t, p, v)
        default: self.init(v, p, q)
        }
    }

    /// Brighten, then desaturate, until the colour reaches `ratio` against `background`.
    /// Used for every FOREGROUND mark derived from content (accent, calendar colour).
    public func legible(on background: RGB = .black, ratio: Double = 4.5) -> RGB {
        var (h, s, v) = hsb
        s = min(s, 0.85); v = max(v, 0.72)
        var out = RGB(h: h, s: s, v: v)
        var guardrail = 0
        while out.contrast(with: background) < ratio && guardrail < 40 {
            if v < 1 { v = min(1, v + 0.04) } else { s = max(0, s - 0.05) }
            out = RGB(h: h, s: s, v: v); guardrail += 1
        }
        return out
    }
    /// Label colour to place ON a filled accent (prominent button, Join capsule).
    public var onColor: RGB { contrast(with: .black) >= contrast(with: .white) ? .black : .white }
    /// Glows read as light: saturated and bright, never neon-white (ambient layer only).
    public var luminous: RGB {
        let (h, s, v) = hsb
        return RGB(h: h, s: min(max(s, 0.45), 0.90), v: min(max(v, 0.75), Glow.maxBrightness))
    }

    public static let black = RGB(0, 0, 0)
    public static let white = RGB(1, 1, 1)
}

// MARK: - Palette (surfaces, lines, text, semantic)

/// One palette per contrast/transparency situation. Text is white at fixed opacities, so it
/// composites identically on every surface. Values are audited in DESIGN.md §2.1.
public nonisolated struct CrannyPalette: Equatable, Sendable {
    public nonisolated enum Variant: String, CaseIterable, Sendable {
        case standard       // default (ambience Off or Subtle)
        case lit            // ambience Vivid, or the glass floating island: denser cards, lifted text
        case highContrast   // System ▸ Accessibility ▸ Increase contrast
        case opaque         // System ▸ Accessibility ▸ Reduce transparency
    }

    /// Raw numbers (white level / opacity) so the contrast audit and the colours share one source.
    public nonisolated struct Spec: Equatable, Sendable {
        public var cardWhite: Double, cardOpacity: Double, cardHoverWhite: Double
        public var control: Double, controlHover: Double, controlPressed: Double, well: Double
        public var scrim: Double, hairline: Double, stroke: Double, keyline: Double
        public var label: Double, secondary: Double, tertiary: Double, quaternary: Double
        /// Card composited over pure black (the colour text actually sits on in the worst-lit case).
        public var cardOverBlack: RGB { RGB(white: cardWhite * cardOpacity) }
    }

    public let variant: Variant
    public let spec: Spec

    // Surfaces
    public var surface: Color { .black }                                         // = hardware notch, never tinted
    public var card: Color { Color(.sRGB, white: spec.cardWhite, opacity: spec.cardOpacity) }   // smoked widget card
    public var cardHover: Color { Color(.sRGB, white: spec.cardHoverWhite, opacity: spec.cardOpacity) }
    public var control: Color { white(spec.control) }                            // buttons, chips, tracks
    public var controlHover: Color { white(spec.controlHover) }
    public var controlPressed: Color { white(spec.controlPressed) }              // pressed + selected segment/row
    public var well: Color { white(spec.well) }                                  // inset text fields
    public var scrim: Color { Color(.sRGB, white: 0, opacity: spec.scrim) }      // under text placed directly on light
    // Lines
    public var hairline: Color { white(spec.hairline) }                          // card edge, flat-style dividers
    public var stroke: Color { white(spec.stroke) }                              // outlines, idle dashed drop zones
    public var keyline: Color { white(spec.keyline) }                            // rim of peek/open (× openness)
    // Text & glyphs
    public var label: Color { white(spec.label) }
    public var secondaryLabel: Color { white(spec.secondary) }
    public var tertiaryLabel: Color { white(spec.tertiary) }
    public var quaternaryLabel: Color { white(spec.quaternary) }                 // placeholders / disabled only
    // Semantic (dark-appearance values; accessible variants under Increase Contrast)
    public var success: Color { SemanticColor.success.rgb(variant == .highContrast).color }
    public var warning: Color { SemanticColor.warning.rgb(variant == .highContrast).color }
    public var danger: Color { SemanticColor.danger.rgb(variant == .highContrast).color }
    public var info: Color { SemanticColor.info.rgb(variant == .highContrast).color }
    public var caution: Color { SemanticColor.caution.rgb(variant == .highContrast).color }
    // Prominent controls: the ONE primary action of a card is filled white with black content (icon buttons, chips)
    public var prominentFill: Color { .white }
    public var onProminent: Color { .black }

    private func white(_ a: Double) -> Color { Color(.sRGB, white: 1, opacity: a) }

    public static func make(_ v: Variant) -> CrannyPalette {
        switch v {
        case .standard:
            return .init(variant: v, spec: .init(
                cardWhite: 0.10, cardOpacity: 0.80, cardHoverWhite: 0.15,
                control: 0.11, controlHover: 0.16, controlPressed: 0.22, well: 0.06,
                scrim: 0.55, hairline: 0.10, stroke: 0.24, keyline: 0.14,
                label: 1.0, secondary: 0.70, tertiary: 0.55, quaternary: 0.32))
        case .lit:
            return .init(variant: v, spec: .init(
                cardWhite: 0.10, cardOpacity: 0.88, cardHoverWhite: 0.15,
                control: 0.11, controlHover: 0.16, controlPressed: 0.22, well: 0.06,
                scrim: 0.62, hairline: 0.12, stroke: 0.26, keyline: 0.18,
                label: 1.0, secondary: 0.76, tertiary: 0.62, quaternary: 0.36))
        case .highContrast:
            return .init(variant: v, spec: .init(
                cardWhite: 0.14, cardOpacity: 1.0, cardHoverWhite: 0.20,
                control: 0.20, controlHover: 0.26, controlPressed: 0.32, well: 0.12,
                scrim: 0.80, hairline: 0.34, stroke: 0.62, keyline: 0.45,
                label: 1.0, secondary: 0.86, tertiary: 0.74, quaternary: 0.50))
        case .opaque:
            return .init(variant: v, spec: .init(
                cardWhite: 0.09, cardOpacity: 1.0, cardHoverWhite: 0.13,
                control: 0.11, controlHover: 0.16, controlPressed: 0.22, well: 0.06,
                scrim: 1.0, hairline: 0.12, stroke: 0.26, keyline: 0.16,
                label: 1.0, secondary: 0.70, tertiary: 0.55, quaternary: 0.32))
        }
    }
}

/// Semantic colours mean only what they mean on iOS. Never decorative.
public nonisolated enum SemanticColor: String, CaseIterable, Sendable {
    case success    // charging, Join, done, "live" (meeting in progress)
    case warning    // timer (iOS convention), last minute, ≤ 20 % battery
    case danger     // ≤ 10 % battery, failed pipeline, destructive
    case info       // links, AirDrop, Bluetooth
    case caution    // Low Power Mode, brightness (coloured HUD)

    public func rgb(_ highContrast: Bool) -> RGB {
        switch self {
        case .success: RGB(hex: highContrast ? 0x30DB5B : 0x30D158)
        case .warning: RGB(hex: highContrast ? 0xFFB340 : 0xFF9F0A)
        case .danger:  RGB(hex: highContrast ? 0xFF6961 : 0xFF453A)
        case .info:    RGB(hex: highContrast ? 0x70B7FF : 0x409CFF)
        case .caution: RGB(hex: highContrast ? 0xFFD426 : 0xFFD60A)
        }
    }
}

/// Brand ramp "Afterglow": app icon, onboarding, About, and the fallback ambient palette.
public nonisolated enum BrandColor {
    public static let mint     = RGB(hex: 0x9EFFEB)
    public static let lagoon   = RGB(hex: 0x2ED3C6)
    public static let sky      = RGB(hex: 0x54C7F2)
    public static let iris     = RGB(hex: 0x8B6CFF)
    public static let rose     = RGB(hex: 0xFF4F8B)
    public static let ember    = RGB(hex: 0xFF7A45)
    public static let night    = RGB(hex: 0x0B0A14)
    public static let graphite = RGB(hex: 0x1E2026)
}

// MARK: - Accent

/// Settings ▸ Appearance ▸ Accent. One accent at a time, for state and progress only
/// (scrubber, rings, visualizer, toggles, focus ring, armed drop target) — never body
/// text, never large fills, never anything with a semantic meaning.
public nonisolated enum AccentSource: Codable, Hashable, Sendable {
    case automatic              // album art while media plays, otherwise the system accent (default)
    case system                 // NSColor.controlAccentColor, lifted for black
    case swatch(AccentSwatch)   // curated, all ≥ 7:1 on black
    case monochrome             // white only ("disable colours")
}

public nonisolated enum AccentSwatch: String, CaseIterable, Codable, Sendable {
    case blue, teal, green, yellow, orange, pink, purple, graphite
    public var rgb: RGB {
        switch self {
        case .blue:     RGB(hex: 0x5CA8FF)
        case .teal:     RGB(hex: 0x4FD1C4)
        case .green:    RGB(hex: 0x66D487)
        case .yellow:   RGB(hex: 0xF5C452)
        case .orange:   RGB(hex: 0xFF9E5C)
        case .pink:     RGB(hex: 0xFF80B5)
        case .purple:   RGB(hex: 0xB89EFF)
        case .graphite: RGB(hex: 0xC7C7CC)
        }
    }
}

public nonisolated enum AccentResolver {
    /// The accent actually drawn. Guarded against the darkest surface it sits on (a card over
    /// black): ≥ 4.5:1, or ≥ 7:1 with Increase Contrast.
    public static func resolve(_ source: AccentSource, albumAccent: RGB?, systemAccent: RGB,
                               palette: CrannyPalette.Spec, increaseContrast: Bool) -> RGB {
        let raw: RGB = switch source {
        case .automatic: albumAccent ?? systemAccent
        case .system: systemAccent
        case .swatch(let s): s.rgb
        case .monochrome: .white
        }
        return raw.legible(on: palette.cardOverBlack, ratio: increaseContrast ? 7 : 4.5)
    }

    /// `NSColor.controlAccentColor` resolved in Dark appearance (Graphite stays grey).
    @MainActor public static func systemAccent() -> RGB {
        var out = RGB(hex: 0x0A84FF)
        NSAppearance(named: .darkAqua)?.performAsCurrentDrawingAppearance {
            if let c = NSColor.controlAccentColor.usingColorSpace(.sRGB) {
                out = RGB(Double(c.redComponent), Double(c.greenComponent), Double(c.blueComponent))
            }
        }
        return out
    }
}

// MARK: - Notes code mode

/// Syntax palette for Notes "code mode" (Markdown + common languages). Each ≥ 4.5:1 on `card`.
public nonisolated enum SyntaxPalette {
    public static let keyword  = RGB(hex: 0xFF7AB8)
    public static let type     = RGB(hex: 0x62D6FF)
    public static let string   = RGB(hex: 0xFF9466)
    public static let number   = RGB(hex: 0xE8C66C)
    public static let function = RGB(hex: 0xA6E37A)
    public static let link     = RGB(hex: 0x6BB3FF)
    /// Comments use `tertiaryLabel` + italic; headings use `label` + semibold.
}
