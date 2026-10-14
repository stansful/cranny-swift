// CrannyCore/DesignSystem/Layout.swift
// Spacing, radii, strokes, hit targets, elevation, glow and the Nook cell grid.
import SwiftUI

/// 4-pt grid with 2/6-pt half steps for optical tweaks.
public nonisolated enum Space {
    public static let xxs: CGFloat = 2
    public static let xs: CGFloat = 4
    public static let s: CGFloat = 6
    public static let m: CGFloat = 8
    public static let l: CGFloat = 12
    public static let xl: CGFloat = 16
    public static let xxl: CGFloat = 20
    public static let xxxl: CGFloat = 24
    public static let huge: CGFloat = 32
}

/// Always `.continuous`. Nested radii are concentric: inner = outer − inset.
/// Notch-anchored radii (closed, hover, compact, ears) live in `NotchLayout` and scale with `unit`.
public nonisolated enum Radius {
    public static let panel: CGFloat = 32        // open Nook bottom corners (Standard density)
    public static let peek: CGFloat = 22         // peek / quick-peek bottom corners
    public static let card: CGFloat = 20         // = panel − padding (all densities)
    public static let inner: CGFloat = 8         // = card − card padding: artwork, wells, thumbnails
    public static let tile: CGFloat = 12         // 56-pt launcher hover well
    public static let artPeek: CGFloat = 10      // 40-pt artwork in a peek row (22 − 12)
    public static let artCompact: CGFloat = 5    // 20-pt artwork in the band (× unit)
    public static let control: CGFloat = 8       // "Rounded" button shape
    public static let chip: CGFloat = 6
    public static let keycap: CGFloat = 4
    public static let focusRingOutset: CGFloat = 3

    public static func concentric(_ outer: CGFloat, inset: CGFloat, minimum: CGFloat = 4) -> CGFloat {
        max(outer - inset, minimum)
    }
}

public nonisolated enum StrokeWidth {
    /// Exactly one device pixel (0.5 pt on Retina).
    public static func hairline(_ displayScale: CGFloat) -> CGFloat { 1 / max(displayScale, 1) }
    public static let regular: CGFloat = 1
    public static let keyline: CGFloat = 1
    public static let emphasis: CGFloat = 1.5         // dashed drop zones
    public static let dash: [CGFloat] = [5, 4]
    public static let focus: CGFloat = 2              // keyboard focus ring (accent)
    public static let scrubber: CGFloat = 4           // 6 while hovered or dragged
    public static let scrubberActive: CGFloat = 6
    public static let hudBar: CGFloat = 6
    public static let ringCompact: CGFloat = 2.5      // rings in the band
    public static let ring: CGFloat = 5               // rings in widgets (timer)
}

/// Minimum interactive sizes (macOS minimum is 20 × 20).
public nonisolated enum HitTarget {
    public static let nook = CGSize(width: 28, height: 24)       // any control inside the Nook
    public static let band = CGSize(width: 32, height: 24)       // embedded controls in compact (Join, ⏯)
    public static let preferred: CGFloat = 28
}

// MARK: - Elevation & glow

public nonisolated struct CrannyShadow: Equatable, Sendable {
    public let opacity: Double, radius: CGFloat, y: CGFloat
    public init(opacity: Double, radius: CGFloat, y: CGFloat) { self.opacity = opacity; self.radius = radius; self.y = y }
    public static let none = CrannyShadow(opacity: 0, radius: 0, y: 0)
}

/// Closed and compact have NO shadow: the shape is part of the bezel and a shadow would reveal
/// the seam. SwiftUI `.shadow` pixels are click-through for the window server (R1 §4.1).
public nonisolated enum Elevation {
    public static let peek: [CrannyShadow] = [.init(opacity: 0.22, radius: 1.5, y: 1), .init(opacity: 0.28, radius: 14, y: 6)]
    public static let open: [CrannyShadow] = [.init(opacity: 0.25, radius: 2, y: 1), .init(opacity: 0.35, radius: 28, y: 12)]
    public static let lifted: [CrannyShadow] = [.init(opacity: 0.50, radius: 12, y: 6)]     // dragged tray tile
    /// Transparent margin the fixed canvas keeps around the largest shape (shadow + underglow).
    public static let canvasMargin: CGFloat = 48
}

public nonisolated enum Glow {
    /// Halo behind artwork in the Media widget and peek (album accent).
    public static let albumHaloOpacity: Double = 0.30
    public static let albumHaloRadius: CGFloat = 36
    /// Coloured light spilling onto the desktop below the open Nook. Vivid only; drawn as a
    /// coloured `.shadow` so it stays click-through.
    public static let underglow = CrannyShadow(opacity: 0.30, radius: 36, y: 10)
    /// Hard caps that the contrast audit assumes. Effects must clamp to these.
    public static let maxBrightness: Double = 0.95
    public static func ambientAlphaCap(_ level: AmbienceLevel) -> Double {
        switch level {
        case .off: 0
        case .subtle: 0.45
        case .vivid: 0.80
        }
    }
}

public extension View {
    /// Two-layer elevation, scaled by `amount` (0 closed … 1 open).
    func crannyElevation(_ layers: [CrannyShadow], amount: Double = 1) -> some View {
        let a = layers.first ?? .none
        let b = layers.count > 1 ? layers[1] : .none
        return self
            .shadow(color: .black.opacity(a.opacity * amount), radius: a.radius, x: 0, y: a.y * amount)
            .shadow(color: .black.opacity(b.opacity * amount), radius: b.radius, x: 0, y: b.y * amount)
    }
}

// MARK: - Buttons

/// Settings ▸ Appearance ▸ Buttons.
public nonisolated enum ButtonShapeStyle: String, CaseIterable, Codable, Sendable { case capsule, rounded }

public nonisolated struct CrannyButtonShape: Shape {
    public var style: ButtonShapeStyle
    public init(_ style: ButtonShapeStyle) { self.style = style }
    public func path(in r: CGRect) -> Path {
        let radius = style == .capsule ? min(r.width, r.height) / 2 : Radius.control
        return RoundedRectangle(cornerRadius: radius, style: .continuous).path(in: r)
    }
}

// MARK: - The Nook grid

/// Settings ▸ Appearance ▸ Density.
public nonisolated enum NookDensity: String, CaseIterable, Codable, Sendable {
    case compact, standard, roomy
    public var cell: CGFloat { switch self { case .compact: 52; case .standard: 56; case .roomy: 64 } }
    public var gutter: CGFloat { switch self { case .compact: 6; case .standard: 8; case .roomy: 10 } }
    public var padding: CGFloat { switch self { case .compact: 10; case .standard: 12; case .roomy: 14 } }
    public var cardPadding: CGFloat { switch self { case .compact: 10; case .standard: 12; case .roomy: 12 } }
    /// Panel radius per density keeps the CARD radius at 20 everywhere (concentric).
    public var panelRadius: CGFloat { Radius.card + padding }
}

/// Settings ▸ Appearance ▸ Widgets: smoked cards (default) or flat with hairline dividers.
public nonisolated enum WidgetStyle: String, CaseIterable, Codable, Sendable { case cards, flat }

public nonisolated struct NookGrid: Equatable, Sendable {
    public var density: NookDensity
    public var textSize: CrannyTextSize
    public var style: WidgetStyle
    public var rows: Int
    /// Settings ▸ Appearance ▸ Panel padding (±4 pt on top of the density). Radii stay concentric.
    public var paddingTune: CGFloat

    public init(density: NookDensity = .standard, textSize: CrannyTextSize = .standard,
                style: WidgetStyle = .cards, rows: Int = 2, paddingTune: CGFloat = 0) {
        self.density = density; self.textSize = textSize; self.style = style; self.rows = rows
        self.paddingTune = min(max(paddingTune, -4), 4)
    }

    /// Larger text grows the cell (rounded to 4 pt), so content never clips.
    public var cell: CGFloat { (density.cell * max(textSize.scale, 1) / 4).rounded() * 4 }
    /// Flat style puts a 1-px divider in the middle of a double gutter.
    public var gutter: CGFloat { style == .flat ? density.gutter * 2 + 1 : density.gutter }
    public var padding: CGFloat { density.padding + paddingTune }
    public var headerGap: CGFloat { 6 }
    public var panelRadius: CGFloat { Radius.card + padding }    // = density.panelRadius when the tune is 0
    public var cardRadius: CGFloat { Radius.concentric(panelRadius, inset: padding) }
    public var innerRadius: CGFloat { Radius.concentric(cardRadius, inset: density.cardPadding) }

    public func width(cells n: Int) -> CGFloat { CGFloat(n) * cell + CGFloat(max(n - 1, 0)) * gutter }
    public var height: CGFloat { CGFloat(rows) * cell + CGFloat(max(rows - 1, 0)) * gutter }
}
