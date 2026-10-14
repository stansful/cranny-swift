// Renders the HUD the way the shell lays out a compact activity and checks what lands where: the glyph left of
// the camera, the bar right of it, nothing over the camera housing. Set CRANNY_SNAPSHOT_DIR=<dir> to also
// write the PNGs to <dir>/HUD for visual review (Debug QA; never needed in CI).
import AppKit
import CrannyCore
import Foundation
import SwiftUI
import Testing
@testable import CrannyHUD

@MainActor @Suite struct HUDRenderTests {
    private struct Case {
        var name: String
        var display: HUDDisplay
        var metrics: NotchMetrics = .reference
        var theme = CrannyTheme()
        var configure: (SettingsStore) -> Void = { _ in }
    }

    private static let island = NotchMetrics(hasNotch: false, notchWidth: 0, bandHeight: 30, screenWidth: 1920)

    private var cases: [Case] {
        var contrast = CrannyTheme()
        contrast.increaseContrast = true
        var colorless = CrannyTheme()
        colorless.differentiateWithoutColor = true
        var instant = CrannyTheme()
        instant.motion = .instant
        return [
            Case(name: "volume", display: HUDDisplay(kind: .volume, level: 0.62)),
            Case(name: "volume-value", display: HUDDisplay(kind: .volume, level: 0.62)) { $0[HUDSettings.showsValue] = true },
            Case(name: "volume-muted", display: HUDDisplay(kind: .volume, level: 0.62, isMuted: true)),
            Case(name: "volume-fine", display: HUDDisplay(kind: .volume, level: 0.453125, showsFineTicks: true)),
            Case(name: "volume-device", display: HUDDisplay(kind: .volume, level: 0.5, deviceGlyph: "airpodspro")),
            Case(name: "volume-device-muted", display: HUDDisplay(kind: .volume, level: 0.5, isMuted: true, deviceGlyph: "airpodspro"),
                 theme: colorless),                                       // speaker.slash.fill and the value
            Case(name: "volume-instant", display: HUDDisplay(kind: .volume, level: 0.5, deviceGlyph: "airpodspro", glyphBounce: 3),
                 theme: instant),
            Case(name: "volume-full", display: HUDDisplay(kind: .volume, level: 1)) { $0[HUDSettings.showsValue] = true },
            Case(name: "volume-zero", display: HUDDisplay(kind: .volume, level: 0)),
            Case(name: "brightness-semantic", display: HUDDisplay(kind: .brightness, level: 0.75)) { $0[HUDSettings.colors] = .semantic },
            Case(name: "brightness-low", display: HUDDisplay(kind: .brightness, level: 0.25)),
            Case(name: "keyboard-semantic", display: HUDDisplay(kind: .keyboardBacklight, level: 0.4)) { $0[HUDSettings.colors] = .semantic },
            Case(name: "volume-accent", display: HUDDisplay(kind: .volume, level: 0.62)) { $0[HUDSettings.colors] = .accent },
            Case(name: "volume-contrast", display: HUDDisplay(kind: .volume, level: 0.62), theme: contrast),
            Case(name: "volume-dwc", display: HUDDisplay(kind: .volume, level: 0.62), theme: colorless),
            Case(name: "island-volume", display: HUDDisplay(kind: .volume, level: 0.62), metrics: Self.island),
            Case(name: "island-value", display: HUDDisplay(kind: .brightness, level: 0.75), metrics: Self.island) {
                $0[HUDSettings.showsValue] = true
            },
        ]
    }

    private func render(_ view: some View) throws -> CGImage {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        return try #require(renderer.cgImage)
    }

    @Test func rendersEveryVariant() throws {
        let directory = SnapshotOutput.directory("HUD")
        for item in cases {
            let activity = previewHUD(item.display, configure: item.configure)
            let preview = HUDBandPreview(activity: activity, metrics: item.metrics, theme: item.theme)
            let image = try render(preview)
            let layout = NotchLayout(metrics: item.metrics)
            let hud = layout.hud
            #expect(CGFloat(image.width) == (hud.outerWidth + 64).rounded() * 2, "\(item.name)")

            // The camera housing (the middle of the band) stays empty: content hugs it from both sides.
            let canvasMid = CGFloat(image.width) / 2
            let middle = layout.middle() * 2
            let bandTop = layout.rowInset * 2, bandBottom = (layout.rowInset + layout.rowHeight) * 2
            let camera = CGRect(x: canvasMid - middle / 2 + 6, y: bandTop + 2, width: middle - 12, height: bandBottom - bandTop - 4)
            #expect(try brightPixels(image, in: camera) == 0, "\(item.name): something drawn over the camera")
            // The glyph sits left of the camera, the bar right of it.
            let slot = SlotWidth.wide.points(unit: layout.u) * 2
            let left = CGRect(x: canvasMid - middle / 2 - slot, y: bandTop, width: slot, height: bandBottom - bandTop)
            let right = CGRect(x: canvasMid + middle / 2, y: bandTop, width: slot, height: bandBottom - bandTop)
            #expect(try brightPixels(image, in: left) > 20, "\(item.name): no glyph")
            if item.display.level > 0 {
                #expect(try brightPixels(image, in: right, threshold: 0.2) > 20, "\(item.name): no bar")
            }

            if let directory {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let data = try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
                try data.write(to: directory.appending(path: "hud-\(item.name).png"))
            }
        }
    }

    @Test func peekRowRenders() throws {
        let row = HUDPeekRow(activity: previewHUD(HUDDisplay(kind: .volume, level: 0.62)))
            .frame(width: 400, height: NotchLayout.peekRow)
            .padding(.horizontal, Space.l)
            .background(.black)
            .crannyThemeRoot(CrannyTheme())
        let image = try render(row)
        #expect(try brightPixels(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height)) > 200)
        if let directory = SnapshotOutput.directory("HUD") {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
            try data.write(to: directory.appending(path: "hud-peek-row.png"))
        }
    }

    /// Pixels in `rect` (image pixels, top-left origin) brighter than the black notch by `threshold`.
    private func brightPixels(_ image: CGImage, in rect: CGRect, threshold: Double = 0.5) throws -> Int {
        let width = image.width, height = image.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        let context = try #require(CGContext(data: &data, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                             space: CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let area = rect.integral.intersection(CGRect(x: 0, y: 0, width: width, height: height))
        var count = 0
        for y in Int(area.minY)..<Int(area.maxY) {
            for x in Int(area.minX)..<Int(area.maxX) {
                let i = (y * width + x) * 4
                let brightness = (Double(data[i]) + Double(data[i + 1]) + Double(data[i + 2])) / (3 * 255)
                if brightness > threshold { count += 1 }
            }
        }
        return count
    }
}
