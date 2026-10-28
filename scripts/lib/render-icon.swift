// scripts/lib/render-icon.swift — renders the two image layers of App/AppIcon.icon, the Icon Composer
// document of the app icon "Light from the nook" (DESIGN.md §15). Original artwork, MIT.
//
//   make icon                                          # = xcrun swift scripts/lib/render-icon.swift App/AppIcon.icon/Assets
//
// Writes notch.png (the notch silhouette, black, hanging from the top edge) and light.png (the fan of light
// beneath it, blended plus-lighter by icon.json). Both are 1024 × 1024 with transparency. The fill, the glass,
// the shadow and the system's macOS 14/15 fallback (AppIcon.icns) come from icon.json and actool.
import CoreGraphics
import Foundation
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "App/AppIcon.icon/Assets", isDirectory: true)
let side = 1024
let canvas = CGRect(x: 0, y: 0, width: side, height: side)
/// DESIGN.md §15 sizes the notch relative to the 824-pt body of the macOS icon grid.
let body: CGFloat = 824

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

/// A transparent sRGB canvas with a top-left origin (y grows downward, like SwiftUI).
func makeContext() -> CGContext {
    guard let space = CGColorSpace(name: CGColorSpace.sRGB),
          let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        fatalError("cannot create a bitmap context")                       // build tool: fail loudly
    }
    ctx.translateBy(x: 0, y: CGFloat(side))
    ctx.scaleBy(x: 1, y: -1)
    ctx.setShouldAntialias(true)
    ctx.interpolationQuality = .high
    return ctx
}

func write(_ ctx: CGContext, _ name: String) {
    let url = outputDirectory.appending(path: name)
    guard let image = ctx.makeImage(),
          let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        fatalError("cannot write \(url.path)")
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { fatalError("cannot write \(url.path)") }
    print("wrote \(url.path)")
}

/// The notch silhouette, built the same way as CrannyCore's `NotchShape` (continuous bottom corners from
/// `UnevenRoundedRectangle`, quarter-circle ears unioned into one outline), hanging from the top edge.
func notchPath(width w: CGFloat, height h: CGFloat, bottomRadius rb: CGFloat, ear e: CGFloat, in rect: CGRect) -> CGPath {
    let bodyRect = CGRect(x: rect.midX - w / 2, y: rect.minY, width: w, height: h)
    let base = UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: rb, bottomTrailingRadius: rb,
                                      topTrailingRadius: 0, style: .continuous).path(in: bodyRect)
    let k: CGFloat = 0.4477
    var ears = Path()
    for side in [-1.0, 1.0] as [CGFloat] {
        let x0 = side < 0 ? bodyRect.minX : bodyRect.maxX
        let xo = x0 + side * e
        let lap = -side * 0.5
        ears.move(to: CGPoint(x: xo, y: bodyRect.minY))
        ears.addLine(to: CGPoint(x: x0 + lap, y: bodyRect.minY))
        ears.addLine(to: CGPoint(x: x0 + lap, y: bodyRect.minY + e))
        ears.addLine(to: CGPoint(x: x0, y: bodyRect.minY + e))
        ears.addCurve(to: CGPoint(x: xo, y: bodyRect.minY),
                      control1: CGPoint(x: x0, y: bodyRect.minY + e * k),
                      control2: CGPoint(x: xo - side * e * (1 - k), y: bodyRect.minY))
        ears.closeSubpath()
    }
    return base.union(ears).cgPath
}

/// A radial gradient squashed vertically by `squash` (1.25 = 25 % flatter than a circle).
func radial(_ ctx: CGContext, center: CGPoint, radius: CGFloat, squash: CGFloat, colors: [CGColor], locations: [CGFloat]) {
    guard let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray,
                                    locations: locations) else { fatalError("bad gradient") }
    ctx.saveGState()
    ctx.translateBy(x: center.x, y: center.y)
    ctx.scaleBy(x: 1, y: 1 / squash)
    ctx.drawRadialGradient(gradient, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: radius, options: [])
    ctx.restoreGState()
}

try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

// 1. Notch: black, 0.40 × 0.15 of the body, ears 0.045, bottom radius 0.06.
let notch = makeContext()
notch.addPath(notchPath(width: 0.40 * body, height: 0.15 * body, bottomRadius: 0.06 * body, ear: 0.045 * body, in: canvas))
notch.setFillColor(rgb(0x000000))
notch.fillPath()
write(notch, "notch.png")

// 2. Light: a mint → sky → iris core spilling from beneath the notch, and a faint rose lobe.
let light = makeContext()
radial(light, center: CGPoint(x: 512, y: 170), radius: 400, squash: 1.25,
       colors: [rgb(0x9EFFEB), rgb(0x54C7F2, 0.85), rgb(0x8B6CFF, 0.35), rgb(0x8B6CFF, 0)],
       locations: [0, 0.38, 0.72, 1])
radial(light, center: CGPoint(x: 650, y: 330), radius: 250, squash: 1.1,
       colors: [rgb(0xFF4F8B, 0.30), rgb(0xFF4F8B, 0)], locations: [0, 1])
// The light comes from beneath the notch: fade it out toward the top edge beside the ears.
if let fade = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                         colors: [rgb(0x000000, 0.12), rgb(0x000000, 1)] as CFArray, locations: [0, 1]) {
    light.setBlendMode(.destinationIn)
    light.drawLinearGradient(fade, start: CGPoint(x: 0, y: 40), end: CGPoint(x: 0, y: 0.15 * body + 70),
                             options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    light.setBlendMode(.normal)
}
write(light, "light.png")
