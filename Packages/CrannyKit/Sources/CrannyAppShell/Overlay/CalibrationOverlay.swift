// CrannyAppShell/Overlay/CalibrationOverlay.swift — Appearance ▸ Notch fit (DESIGN.md §3.1, ARCHITECTURE.md §5.9):
// while a slider is dragged, a 1-px accent outline of the closed shape sits over the camera housing and a 2× loupe
// beside it magnifies the trailing bottom corner, where a misfit shows first. Static drawing: no timers. The
// panel freezes in the breath meanwhile (`NotchControl.setCalibrationOverlay`), so the outline stays readable.
import CrannyCore
import SwiftUI

struct CalibrationOverlay: View {
    @Environment(\.cranny) private var theme
    @Environment(\.displayScale) private var displayScale
    let layout: NotchLayout

    /// Loupe diameter and magnification.
    static let loupeDiameter: CGFloat = 88
    static let magnification: CGFloat = 2

    var body: some View {
        GeometryReader { proxy in
            let canvas = CGRect(origin: .zero, size: proxy.size)
            let closed = layout.closed
            ZStack(alignment: .topLeading) {
                NotchShape(closed)
                    .stroke(theme.accentColor, lineWidth: StrokeWidth.hairline(displayScale))
                Loupe(closed: closed, canvas: canvas, corner: Self.corner(of: closed, in: canvas))
                    .frame(width: Self.loupeDiameter, height: Self.loupeDiameter)
                    .offset(Self.loupeOrigin(for: closed, in: canvas))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)                                               // Settings describes the values
    }

    /// The closed shape's trailing bottom corner, in canvas coordinates (top-left origin).
    static func corner(of closed: NotchGeometry, in canvas: CGRect) -> CGPoint {
        CGPoint(x: canvas.midX + closed.bodyWidth / 2, y: canvas.minY + closed.bottom)
    }

    /// Below and beside the corner, inside the canvas.
    static func loupeOrigin(for closed: NotchGeometry, in canvas: CGRect) -> CGSize {
        let corner = corner(of: closed, in: canvas)
        let x = min(corner.x + Space.l, canvas.maxX - loupeDiameter)
        let y = min(corner.y + Space.m, canvas.maxY - loupeDiameter)
        return CGSize(width: x, height: y)
    }
}

/// The magnified corner: the closed shape (surface black) on a neutral control fill, with its outline.
private struct Loupe: View {
    @Environment(\.cranny) private var theme
    @Environment(\.displayScale) private var displayScale
    let closed: NotchGeometry
    let canvas: CGRect
    let corner: CGPoint

    var body: some View {
        let palette = theme.palette
        Canvas { context, size in
            let scale = CalibrationOverlay.magnification
            context.translateBy(x: size.width / 2, y: size.height / 2)
            context.scaleBy(x: scale, y: scale)
            context.translateBy(x: -corner.x, y: -corner.y)
            let path = NotchShape(closed).path(in: canvas)
            context.fill(path, with: .color(palette.surface))
            context.stroke(path, with: .color(theme.accentColor), lineWidth: StrokeWidth.hairline(displayScale))
        }
        .background(palette.controlPressed)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(palette.stroke, lineWidth: StrokeWidth.regular))
        .crannyElevation(Elevation.peek)
    }
}

#Preview("Calibration · 14″ notch") {
    CalibrationOverlay(layout: NotchLayout(metrics: .reference))
        .frame(width: 900, height: 282)
        .background(Color.black)
        .crannyThemeRoot(CrannyTheme())
}

#Preview("Calibration · floating island") {
    CalibrationOverlay(layout: NotchLayout(metrics: NotchMetrics(hasNotch: false, notchWidth: 0, bandHeight: 30, screenWidth: 1920)))
        .frame(width: 944, height: 286)
        .background(Color.black)
        .crannyThemeRoot(CrannyTheme())
}
