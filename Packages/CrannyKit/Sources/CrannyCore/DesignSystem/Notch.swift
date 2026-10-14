// CrannyCore/DesignSystem/Notch.swift
// One shape, six animatable numbers, every state. The canvas window never resizes;
// only `NotchShape.animatableData` animates.
import SwiftUI
import AppKit

// MARK: - Measured hardware

public nonisolated struct NotchMetrics: Equatable, Sendable {
    public var hasNotch: Bool
    public var notchWidth: CGFloat     // camera-housing width (0 without a notch)
    public var bandHeight: CGFloat     // notch height on notched displays, else the menu-bar height
    public var screenWidth: CGFloat
    public var displayScale: CGFloat

    public init(hasNotch: Bool, notchWidth: CGFloat, bandHeight: CGFloat, screenWidth: CGFloat, displayScale: CGFloat = 2) {
        self.hasNotch = hasNotch; self.notchWidth = notchWidth; self.bandHeight = bandHeight
        self.screenWidth = screenWidth; self.displayScale = displayScale
    }

    /// 1.0 on a 32-pt notch (14″/16″ MacBook Pro, default scaling). The physical notch is fixed
    /// in pixels, so its height in points encodes display scaling: band-anchored sizes × unit.
    public var unit: CGFloat { min(max(bandHeight / 32, 0.8), 1.25) }

    /// Reference machine used by every table in DESIGN.md.
    public static let reference = NotchMetrics(hasNotch: true, notchWidth: 185, bandHeight: 32, screenWidth: 1512)

    /// Measure — never hard-code. Re-run on `NSApplication.didChangeScreenParametersNotification`.
    @MainActor public static func measure(_ screen: NSScreen) -> NotchMetrics {
        let f = screen.frame
        let top = screen.safeAreaInsets.top
        if top > 0, let l = screen.auxiliaryTopLeftArea, let r = screen.auxiliaryTopRightArea,
           l.width > 0, r.width > 0, f.width - l.width - r.width > 0 {
            return NotchMetrics(hasNotch: true, notchWidth: f.width - l.width - r.width, bandHeight: top,
                                screenWidth: f.width, displayScale: screen.backingScaleFactor)
        }
        // No notch: the band is the menu bar. NSStatusBar.thickness is stale (22) — measure the top inset.
        let menuBar = f.maxY - screen.visibleFrame.maxY
        return NotchMetrics(hasNotch: false, notchWidth: 0, bandHeight: menuBar > 0 ? menuBar : 30,
                            screenWidth: f.width, displayScale: screen.backingScaleFactor)
    }
}

/// Settings ▸ Appearance ▸ On displays without a notch.
public nonisolated enum NoNotchStyle: String, CaseIterable, Codable, Sendable {
    case floatingIsland   // default: detached pill under the menu bar, all corners round
    case attached         // a small tab hanging from the top edge, with ears (notch look)
    case off              // Cranny does not appear on this display
}

// MARK: - Geometry (animatable)

public nonisolated struct NotchGeometry: VectorArithmetic, Sendable {
    public var bodyWidth: CGFloat      // black body, excluding ears
    public var height: CGFloat         // body height (below topInset)
    public var bottomRadius: CGFloat   // convex, continuous
    public var earRadius: CGFloat      // concave flare into the screen's top edge (attached only)
    public var topRadius: CGFloat      // convex top corners (floating only)
    public var topInset: CGFloat       // 0 = attached to the top edge; > 0 = floating island

    public init(bodyWidth: CGFloat, height: CGFloat, bottomRadius: CGFloat, earRadius: CGFloat,
                topRadius: CGFloat = 0, topInset: CGFloat = 0) {
        self.bodyWidth = bodyWidth; self.height = height; self.bottomRadius = bottomRadius
        self.earRadius = earRadius; self.topRadius = topRadius; self.topInset = topInset
    }

    public static var zero: NotchGeometry { .init(bodyWidth: 0, height: 0, bottomRadius: 0, earRadius: 0) }
    public static func + (a: Self, b: Self) -> Self {
        .init(bodyWidth: a.bodyWidth + b.bodyWidth, height: a.height + b.height, bottomRadius: a.bottomRadius + b.bottomRadius,
              earRadius: a.earRadius + b.earRadius, topRadius: a.topRadius + b.topRadius, topInset: a.topInset + b.topInset)
    }
    public static func - (a: Self, b: Self) -> Self {
        .init(bodyWidth: a.bodyWidth - b.bodyWidth, height: a.height - b.height, bottomRadius: a.bottomRadius - b.bottomRadius,
              earRadius: a.earRadius - b.earRadius, topRadius: a.topRadius - b.topRadius, topInset: a.topInset - b.topInset)
    }
    public mutating func scale(by rhs: Double) {
        let k = CGFloat(rhs)
        bodyWidth *= k; height *= k; bottomRadius *= k; earRadius *= k; topRadius *= k; topInset *= k
    }
    public var magnitudeSquared: Double {
        Double(bodyWidth * bodyWidth + height * height + bottomRadius * bottomRadius
               + earRadius * earRadius + topRadius * topRadius + topInset * topInset)
    }

    /// Ears fade out over the first 2 pt of detaching, so attached ⇄ floating is one morph.
    public var attachment: CGFloat { max(0, 1 - topInset / 2) }
    public var outerWidth: CGFloat { bodyWidth + 2 * max(earRadius, 0) * attachment }
    public var bottom: CGFloat { topInset + height }
    public var isFloating: Bool { topInset > 0.5 }
}

// MARK: - Shape

/// Centred horizontally in its rect and top-aligned. Host it in the FIXED canvas.
/// Bottom (and floating top) corners use Apple's continuous curve via `UnevenRoundedRectangle`;
/// the ears are quarter-circle cubics unioned into ONE outline (macOS 14 `Path.union`), so a
/// stroke (the keyline) never shows an internal seam.
public nonisolated struct NotchShape: Shape {
    public var geometry: NotchGeometry
    public init(_ geometry: NotchGeometry) { self.geometry = geometry }

    public var animatableData: NotchGeometry {
        get { geometry }
        set { geometry = newValue }
    }

    public func path(in rect: CGRect) -> Path {
        let g = geometry
        let w = max(g.bodyWidth, 0), h = max(g.height, 0)
        guard w > 0.5, h > 0.5 else { return Path() }
        let body = CGRect(x: rect.midX - w / 2, y: rect.minY + max(g.topInset, 0), width: w, height: h)
        let rb = min(max(g.bottomRadius, 0), h / 2, w / 2)
        let rt = min(max(g.topRadius, 0), h - rb, w / 2)
        let base = UnevenRoundedRectangle(topLeadingRadius: rt, bottomLeadingRadius: rb,
                                          bottomTrailingRadius: rb, topTrailingRadius: rt,
                                          style: .continuous).path(in: body)
        let e = min(max(g.earRadius, 0) * g.attachment, h - rb, body.minX - rect.minX)
        guard e > 0.25 else { return base }

        let k: CGFloat = 0.4477                              // 1 − 0.5523: cubic ≈ quarter circle
        var ears = Path()
        for side in [-1.0, 1.0] as [CGFloat] {
            let x0 = side < 0 ? body.minX : body.maxX       // body edge
            let xo = x0 + side * e                          // ear tip on the screen edge
            let lap = -side * 0.5                           // overlap into the body: no AA seam
            ears.move(to: CGPoint(x: xo, y: body.minY))
            ears.addLine(to: CGPoint(x: x0 + lap, y: body.minY))
            ears.addLine(to: CGPoint(x: x0 + lap, y: body.minY + e))
            ears.addLine(to: CGPoint(x: x0, y: body.minY + e))
            ears.addCurve(to: CGPoint(x: xo, y: body.minY),
                          control1: CGPoint(x: x0, y: body.minY + e * k),
                          control2: CGPoint(x: xo - side * e * (1 - k), y: body.minY))
            ears.closeSubpath()
        }
        return base.union(ears)
    }
}

// MARK: - Compact slots

/// Width of ONE side slot (outer margin 12 + content + 8 gap to the camera), × unit.
/// Both sides always take the wider class, so the camera stays optically centred.
public nonisolated enum SlotWidth: Int, CaseIterable, Comparable, Sendable {
    case none, glyph, short, medium, wide
    public var base: CGFloat {
        switch self {
        case .none: 0
        case .glyph: 40     // 20-pt artwork, a glyph, a 16-pt ring
        case .short: 52     // 5-bar visualizer, "82%"
        case .medium: 68    // "4:59", "in 4m", Join capsule, battery ring + value
        case .wide: 92      // HUD: glyph | level bar 64 (+ optional value)
        }
    }
    public func points(unit: CGFloat) -> CGFloat { (base * unit).rounded() }
    public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
}

// MARK: - Per-state geometry

public nonisolated struct NotchLayout: Equatable, Sendable {
    public var metrics: NotchMetrics
    public var noNotchStyle: NoNotchStyle
    public var widthTune: CGFloat      // Settings ▸ Appearance ▸ Notch fit: −10…+10 pt, 0.5 steps
    public var radiusTune: CGFloat     // −3…+3 pt
    public var grid: NookGrid

    public static let peekRow: CGFloat = 52
    /// The visual at the start of a peek row: artwork, ring or glyph well (DESIGN.md §9.3).
    public static let peekVisual: CGFloat = 40
    public static let satelliteDiameter: CGFloat = 24

    public init(metrics: NotchMetrics, noNotchStyle: NoNotchStyle = .floatingIsland,
                widthTune: CGFloat = 0, radiusTune: CGFloat = 0, grid: NookGrid = NookGrid()) {
        self.metrics = metrics; self.noNotchStyle = noNotchStyle
        self.widthTune = widthTune; self.radiusTune = radiusTune; self.grid = grid
    }

    public var u: CGFloat { metrics.unit }
    public var band: CGFloat { metrics.bandHeight }
    public var isFloating: Bool { !metrics.hasNotch && noNotchStyle == .floatingIsland }
    /// The compact/HUD row: the hardware notch height, or a pill inside the menu bar.
    public var rowHeight: CGFloat { isFloating ? max(band - 6, 22) : band }
    public var rowInset: CGFloat { isFloating ? 3 : 0 }
    /// The Nook header row lives in the band (tabs left of the camera, actions right).
    public var headerHeight: CGFloat { max(band, 28) }

    /// The content-free middle: the camera housing, or a label/gap on displays without a notch.
    public func middle(label: CGFloat = 0) -> CGFloat {
        metrics.hasNotch ? metrics.notchWidth + widthTune : max(label, 12)
    }

    /// CLOSED: exactly the cutout, inset 0.5 pt per side so anti-aliasing never peeks out.
    public var closed: NotchGeometry {
        if metrics.hasNotch {
            let r = min(max((0.30 * band).rounded(), 6), 12) + radiusTune
            return .init(bodyWidth: metrics.notchWidth + widthTune - 1, height: band - 0.5, bottomRadius: r, earRadius: 0)
        }
        switch noNotchStyle {
        case .floatingIsland: return .init(bodyWidth: 64, height: 5, bottomRadius: 2.5, earRadius: 0, topRadius: 2.5, topInset: 4)
        case .attached:       return .init(bodyWidth: 64, height: 5, bottomRadius: 2.5, earRadius: 2)
        case .off:            return .zero
        }
    }

    /// HOVER "breath": acknowledges the dwell before anything opens.
    public var hover: NotchGeometry {
        var g = closed
        if metrics.hasNotch {
            g.bodyWidth += 12 * u; g.height += 3 * u; g.earRadius = 4 * u; g.bottomRadius += 2 * u
        } else if noNotchStyle != .off {
            g.bodyWidth += 24; g.height += 3; g.bottomRadius = g.height / 2
            if isFloating { g.topRadius = g.height / 2 } else { g.earRadius = 3 }
        }
        return g
    }

    /// COMPACT live activity: band height, widened symmetrically by two slots.
    public func compact(_ slot: SlotWidth, label: CGFloat = 0) -> NotchGeometry {
        let w = middle(label: label) + 2 * slot.points(unit: u)
        let h = rowHeight
        if isFloating { return .init(bodyWidth: w, height: h, bottomRadius: h / 2, earRadius: 0, topRadius: h / 2, topInset: rowInset) }
        return .init(bodyWidth: w, height: h, bottomRadius: 13 * u, earRadius: 6 * u)
    }

    /// HUD: the widest compact form. It never adds height, so it never covers content.
    public var hud: NotchGeometry { compact(.wide) }

    /// PEEK: the compact row stays, 52-pt rows grow below it.
    public func peek(rows: Int = 1) -> NotchGeometry {
        let base = metrics.hasNotch ? metrics.notchWidth + widthTune : 180
        let w = min(max(base + 240 * u, 380), 460)
        let h = rowHeight + CGFloat(min(max(rows, 1), 4)) * Self.peekRow + 8
        if isFloating { return .init(bodyWidth: w, height: h, bottomRadius: Radius.peek, earRadius: 0, topRadius: Radius.peek, topInset: rowInset) }
        return .init(bodyWidth: w, height: h, bottomRadius: Radius.peek, earRadius: 8 * u)
    }

    /// OPEN: grid-driven; never narrower than the header needs, never wider than `maxWidth`.
    public func open(columns: Int, rows: Int = 2) -> NotchGeometry {
        var gr = grid; gr.rows = rows
        let cols = min(max(columns, 1), maxColumns)
        let width = min(max(gr.width(cells: cols) + 2 * gr.padding, middle() + 2 * 160), maxWidth)
        let h = headerHeight + gr.headerGap + gr.height + gr.padding
        if isFloating {
            return .init(bodyWidth: width, height: h, bottomRadius: gr.panelRadius, earRadius: 0, topRadius: gr.panelRadius, topInset: 6)
        }
        return .init(bodyWidth: width, height: h, bottomRadius: gr.panelRadius, earRadius: 10 * u)
    }

    /// The Nook never exceeds 55 % of the screen or 880 pt, so menu-bar extras stay reachable.
    public var maxWidth: CGFloat { min(metrics.screenWidth * 0.55, 880) }
    public var maxColumns: Int {
        max(4, Int((maxWidth - 2 * grid.padding + grid.gutter) / (grid.cell + grid.gutter)))
    }

    /// Second concurrent activity: a detached black circle 6u beside the compact body.
    public func satelliteFrame(beside compact: NotchGeometry, in canvas: CGRect) -> CGRect {
        let d = Self.satelliteDiameter * u
        let x = canvas.midX + compact.bodyWidth / 2 + 6 * u
        let y = canvas.minY + rowInset + (rowHeight - d) / 2
        return CGRect(x: x, y: y, width: d, height: d)
    }

    /// Fixed canvas (panel) size: the largest shape (Notes focus = 3 rows) + margins.
    /// Resize it only while closed, when layout settings change (R1 §4.3).
    public var canvasSize: CGSize {
        let o = open(columns: maxColumns, rows: 3)
        return CGSize(width: (o.outerWidth + 2 * Elevation.canvasMargin).rounded(.up),
                      height: (o.bottom + Elevation.canvasMargin).rounded(.up))
    }
}
