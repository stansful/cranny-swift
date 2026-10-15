// CrannySettingsUI/Stage/WallpaperSource.swift — the user's own wallpaper behind the preview stage (DESIGN.md §11.2),
// read ONLY when the file lies outside the folders macOS protects with a Files & Folders prompt
// (`ProtectedLocations`): reading those from Settings would raise a privacy prompt nobody asked for
// (ARCHITECTURE §10.15); the stage then shows the neutral gradient. Decoding happens off the main actor into a
// small thumbnail (about 2 MB). While Settings is open, only the last one per display is kept, for its URL: the stage
// reappearing on the same wallpaper needs no decode (nor does a stage that imitates another display meanwhile), and a
// changed wallpaper replaces its display's miniature instead of adding one per URL. Closing Settings purges them
// (`purge()`), so the next open decodes again, as the first one did.
import AppKit
import CoreGraphics
import CrannyCore
import Foundation
import ImageIO
import os

nonisolated private let log = Log.logger(.settings)

enum WallpaperSource {
    /// A decoded miniature plus whether its top band is light (the menu bar miniature then uses dark content).
    struct Miniature: @unchecked Sendable {   // CGImage is immutable and thread-safe
        let image: CGImage
        let topIsLight: Bool
    }

    // MARK: Loading

    /// Per display (`NSScreenNumber`), the last miniature decoded, with its wallpaper's URL.
    @MainActor private static var last: [UInt32: (url: URL, miniature: Miniature)] = [:]
    /// Bumped by `purge()`: a decode on its way then is not kept.
    @MainActor private static var generation = 0

    /// The miniature of the wallpaper on `screen`, or nil (unsafe location, unreadable or a video wallpaper).
    @MainActor static func miniature(for screen: NSScreen, maxPixelSize: Int = 960) async -> Miniature? {
        guard let url = NSWorkspace.shared.desktopImageURL(for: screen) else { return nil }
        let display = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
        if let cached = last[display], cached.url == url { return cached.miniature }
        let started = generation
        let miniature = await decode(url, maxPixelSize: maxPixelSize)
        if let miniature, generation == started { last[display] = (url, miniature) }
        return miniature
    }

    /// Forgets every miniature (Settings closed; the stage holds none then).
    @MainActor static func purge() {
        last.removeAll()
        generation += 1
    }

    /// The safety check (it may read symbolic links), thumbnail decode and top-band luminance, off the main actor.
    @concurrent private static func decode(_ url: URL, maxPixelSize: Int) async -> Miniature? {
        guard ProtectedLocations.isSafeToRead(url) else {
            log.info("wallpaper is in a protected place; using the neutral stage")
            return nil
        }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return Miniature(image: image, topIsLight: topLuminance(of: image) > 0.6)
    }

    /// Mean luminance of the top 8 % of `image` (where the menu bar sits), from a 16 × 2 downsample.
    nonisolated static func topLuminance(of image: CGImage) -> Double {
        let width = 16, height = 2
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
                  let top = image.cropping(to: CGRect(x: 0, y: 0, width: image.width,
                                                      height: max(1, image.height * 8 / 100))) else { return false }
            context.draw(top, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return 0 }
        var sum = 0.0
        for i in stride(from: 0, to: pixels.count, by: 4) {
            sum += RGB(Double(pixels[i]) / 255, Double(pixels[i + 1]) / 255, Double(pixels[i + 2]) / 255).luminance
        }
        return sum / Double(width * height)
    }
}
