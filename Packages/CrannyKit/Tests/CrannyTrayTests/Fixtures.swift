// Test fixtures: throw-away folders and generated files. Tests never read or write the user's files.
import CoreGraphics
import CoreText
import CrannyCore
import Foundation
import ImageIO
import UniformTypeIdentifiers
@testable import CrannyTray

nonisolated enum Fixtures {
    /// A fresh folder under the system temporary directory.
    static func folder(_ label: String = "t") -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "cranny-tray-tests/\(label)-\(UUID().uuidString)", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// An image file. `noise` makes it photographic (compressible); `orientation` writes the EXIF tag only.
    @discardableResult
    static func image(_ name: String, in folder: URL, width: Int = 400, height: Int = 300, type: UTType = .png,
                      orientation: Int = 1, alpha: Bool = false, noise: Bool = true, gps: Bool = false,
                      quality: Double? = nil) -> URL {
        let url = folder.appending(path: name)
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let info = alpha ? CGImageAlphaInfo.premultipliedLast.rawValue : CGImageAlphaInfo.noneSkipLast.rawValue
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: space, bitmapInfo: info) else { return url }
        if alpha { context.clear(CGRect(x: 0, y: 0, width: width, height: height)) }
        context.setFillColor(CGColor(srgbRed: 0.9, green: 0.4, blue: 0.2, alpha: 1))
        context.fill(CGRect(x: width / 4, y: height / 4, width: width / 2, height: height / 2))
        if noise, let data = context.data {
            let pixels = data.bindMemory(to: UInt8.self, capacity: width * height * 4)
            var seed: UInt32 = 42
            for i in stride(from: 0, to: width * height * 4, by: 4) {
                seed = seed &* 1_664_525 &+ 1_013_904_223
                let value = UInt8(truncatingIfNeeded: seed >> 24)
                pixels[i] = value; pixels[i + 1] = value &+ 40; pixels[i + 2] = value &+ 90
                if !alpha { pixels[i + 3] = 255 }
            }
        }
        guard let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil) else { return url }
        var properties: [CFString: Any] = [kCGImagePropertyOrientation: orientation]
        if gps { properties[kCGImagePropertyGPSDictionary] = [kCGImagePropertyGPSLatitude: 59.93, kCGImagePropertyGPSLatitudeRef: "N"] }
        if let quality { properties[kCGImageDestinationLossyCompressionQuality] = quality }
        properties[kCGImagePropertyExifDictionary] = [kCGImagePropertyExifUserComment: "fixture"]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        CGImageDestinationFinalize(destination)
        return url
    }

    /// An image of black text on white (OCR).
    static func textImage(_ text: String, in folder: URL) -> URL {
        let url = folder.appending(path: "text.png")
        let width = 900, height = 240
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return url }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let font = CTFontCreateWithName("Helvetica-Bold" as CFString, 96, nil)
        let attributed = CFAttributedStringCreateMutable(nil, 0)
        CFAttributedStringReplaceString(attributed, CFRange(location: 0, length: 0), text as CFString)
        let range = CFRange(location: 0, length: CFAttributedStringGetLength(attributed))
        CFAttributedStringSetAttribute(attributed, range, kCTFontAttributeName, font)
        CFAttributedStringSetAttribute(attributed, range, kCTForegroundColorAttributeName, CGColor(gray: 0, alpha: 1))
        if let attributed {
            let line = CTLineCreateWithAttributedString(attributed)
            context.textPosition = CGPoint(x: 40, y: 80)
            CTLineDraw(line, context)
        }
        if let image = context.makeImage(),
           let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) {
            CGImageDestinationAddImage(destination, image, nil)
            CGImageDestinationFinalize(destination)
        }
        return url
    }

    @discardableResult
    static func text(_ name: String, in folder: URL, contents: String = "hello tray\n") -> URL {
        let url = folder.appending(path: name)
        try? contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    static func properties(of url: URL) -> [CFString: Any] {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { return [:] }
        return properties
    }

    static func type(of url: URL) -> UTType? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), let id = CGImageSourceGetType(source) else { return nil }
        return UTType(id as String)
    }

    static func size(_ url: URL) -> Int64 { ImageSteps.fileSize(url) }
}

