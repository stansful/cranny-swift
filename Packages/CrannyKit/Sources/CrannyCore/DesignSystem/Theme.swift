// CrannyCore/DesignSystem/Theme.swift
// One environment value. Feature modules read `@Environment(\.cranny)` and never
// write literal colours, sizes, radii or animations, and never read raw a11y flags.
import SwiftUI

/// Settings ▸ Appearance ▸ Ambient light (the optional "Afterglow" layer, DESIGN.md §5).
public nonisolated enum AmbienceLevel: String, CaseIterable, Codable, Sendable, Comparable {
    case off, subtle, vivid
    public var intensity: Double { switch self { case .off: 0; case .subtle: 0.55; case .vivid: 1 } }
    private var rank: Int { switch self { case .off: 0; case .subtle: 1; case .vivid: 2 } }
    public static func < (a: Self, b: Self) -> Bool { a.rank < b.rank }
}

public nonisolated enum AmbientEffect: String, CaseIterable, Codable, Sendable {
    case aurora   // MeshGradient (15+) / Canvas curtains (14) — default
    case motes    // slow rising specks
    case tide     // luminous wave lines along the bottom edge
    case halo     // one static bloom (Low Power Mode fallback)
}

/// Settings ▸ Appearance ▸ Light ▸ Quality: how the ambient light (and the light's moments) are drawn (DESIGN.md §5.1).
public nonisolated enum AmbientDetail: String, CaseIterable, Codable, Sendable {
    /// The default: the Metal light (CrannyEffects' dedicated Metal layer and shaders, DESIGN.md §5.6).
    case detailed
    /// A simpler light of Core Animation layers that the window server animates: no Metal in Cranny, so no GPU
    /// memory charged to the app and no wake-up per frame (DESIGN.md §5.7). Moments play their still variants.
    case efficient
}

public nonisolated struct CrannyTheme: Equatable, Sendable {
    // User settings
    public var accent: RGB = RGB(hex: 0x409CFF)        // already resolved by AccentResolver
    public var textSize: CrannyTextSize = .standard
    public var density: NookDensity = .standard
    public var widgetStyle: WidgetStyle = .cards
    public var buttonShape: ButtonShapeStyle = .capsule
    public var panelPaddingTune: CGFloat = 0               // ±4 pt (Appearance ▸ Panel padding)
    public var motion: MotionPersonality = .standard
    public var ambience: AmbienceLevel = .subtle
    public var effect: AmbientEffect = .aurora
    /// How the light is drawn: the Metal light (default) or the Core Animation light (Settings ▸ Appearance ▸ Quality).
    public var ambientDetail: AmbientDetail = .detailed
    public var translucentBackground = false
    public var glassIsland = false                       // Liquid Glass island (26+); set by the panel only on floating-style displays
    public var hapticsEnabled = true
    public var notchUnit: CGFloat = 1
    // System state — resolved by CrannyThemeRoot, never set by features
    public var reduceMotion = false
    public var reduceTransparency = false
    public var increaseContrast = false
    public var differentiateWithoutColor = false
    public var voiceOverRunning = false

    public init() {}

    public var effectiveAmbience: AmbienceLevel {
        if reduceTransparency { return .off }
        if increaseContrast || widgetStyle == .flat { return min(ambience, .subtle) }
        return ambience
    }
    public var paletteVariant: CrannyPalette.Variant {
        if increaseContrast { return .highContrast }
        if reduceTransparency { return .opaque }
        if effectiveAmbience == .vivid || glassIsland { return .lit }
        return .standard
    }
    public var palette: CrannyPalette { .make(paletteVariant) }
    public var grid: NookGrid { NookGrid(density: density, textSize: textSize, style: widgetStyle, paddingTune: panelPaddingTune) }
    public var accentColor: Color { accent.color }
    public var accentContrast: Double { increaseContrast ? 7 : 4.5 }
    public var allowsUnderglow: Bool { effectiveAmbience == .vivid }

    public func animation(_ k: CrannyMotion.Kind) -> Animation? {
        CrannyMotion.animation(k, personality: motion, reduceMotion: reduceMotion)
    }

    /// Symbols may animate (DESIGN.md §14.1: no symbol effects under Reduce Motion; §4.2: none under Instant).
    public var animatesSymbols: Bool { !reduceMotion && motion != .instant }
    /// The content transition of a glyph that toggles (pin, play/pause, the HUD glyph):
    /// `.contentTransition(theme.symbolReplace)` — `.symbolEffect(.replace)`, or `.identity` when symbols must not move.
    public var symbolReplace: ContentTransition { animatesSymbols ? .symbolEffect(.replace) : .identity }
}

public extension EnvironmentValues {
    @Entry var cranny: CrannyTheme = CrannyTheme()
}

/// Apply once at the root of every Cranny surface (notch panel, Settings preview stage,
/// onboarding stage). Merges user settings with the live system accessibility state.
public struct CrannyThemeRoot: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    public var base: CrannyTheme
    public init(_ base: CrannyTheme) { self.base = base }

    public func body(content: Content) -> some View {
        var t = base
        t.reduceMotion = base.reduceMotion || reduceMotion
        t.reduceTransparency = base.reduceTransparency || reduceTransparency
        t.increaseContrast = base.increaseContrast || contrast == .increased
        t.differentiateWithoutColor = base.differentiateWithoutColor || differentiateWithoutColor
        t.voiceOverRunning = base.voiceOverRunning || voiceOver
        t.accent = t.accent.legible(on: t.palette.spec.cardOverBlack, ratio: t.accentContrast)
        return content
            .environment(\.cranny, t)
            .environment(\.colorScheme, .dark)     // the notch is always dark
            .tint(t.accent.color)
    }
}

public extension View {
    func crannyThemeRoot(_ theme: CrannyTheme) -> some View { modifier(CrannyThemeRoot(theme)) }
}
