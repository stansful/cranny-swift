// CrannyTray/Pipelines/ImageSteps.swift — Compress, Convert, Resize and Strip metadata with ImageIO (ARCHITECTURE.md
// §7.8, R3 §8). Synchronous and `nonisolated`: `PipelineRunner` calls them from its `@concurrent` context, one file
// at a time, checking for cancellation in between. Each step writes ONE new file into `directory` and returns it;
// it never touches its input.
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

nonisolated enum ImageSteps {
    /// UTType identifiers ImageIO can write on this Mac (AVIF on macOS 27, never WebP or JPEG XL; R3 §8).
    static let writableTypeIdentifiers: Set<String> = Set((CGImageDestinationCopyTypeIdentifiers() as? [String]) ?? [])

    static func canWrite(_ format: TrayImageFormat) -> Bool { writableTypeIdentifiers.contains(format.type.identifier) }
    /// The formats offered in Convert ▾ and the pipeline editor.
    static var writableFormats: [TrayImageFormat] { TrayImageFormat.allCases.filter(canWrite) }

    // MARK: Steps

    /// HEIC (HEIC sources and images with transparency) or JPEG at `quality`, same pixel size, metadata kept.
    /// Throws `.notSmaller` instead of writing a bigger file.
    static func compress(_ input: URL, quality: Double, into directory: URL, naming: OutputNaming) throws -> URL {
        let image = try ImageFile(input)
        let wantsHEIC = image.format == .heic || image.hasAlpha
        let format: TrayImageFormat = wantsHEIC && canWrite(.heic) ? .heic : .jpeg
        let output = OutputNaming.uniqueURL(base: naming.compressed(image.baseName), ext: format.fileExtension, in: directory)
        try reencode(image, as: format, quality: quality, to: output)
        let before = fileSize(input), after = fileSize(output)
        if after >= before {
            try? FileManager.default.removeItem(at: output)
            throw TrayError.notSmaller
        }
        return output
    }

    /// Same pixels in another format (metadata kept; transparency flattened onto white for JPEG).
    static func convert(_ input: URL, to format: TrayImageFormat, quality: Double, into directory: URL) throws -> URL {
        let image = try ImageFile(input)
        guard canWrite(format) else { throw TrayError.formatUnavailable(format.displayName) }
        let output = OutputNaming.uniqueURL(base: image.baseName, ext: format.fileExtension, in: directory)
        try reencode(image, as: format, quality: quality, to: output)
        return output
    }

    /// Scales so the longer side is `percent` % (or at most `pixels`; 0 = `defaultMaxDimension`). Orientation is applied
    /// to the pixels and the tag reset to 1, so the result looks the same everywhere. Never enlarges.
    static func resize(_ input: URL, to target: TrayResize, defaultMaxDimension: Int, quality: Double,
                       into directory: URL, naming: OutputNaming) throws -> URL {
        let image = try ImageFile(input)
        let longest = max(image.orientedWidth, image.orientedHeight)
        let pixels = targetLongestSide(longest: longest, target: target, defaultMaxDimension: defaultMaxDimension)
        guard let resized = image.oriented(maxPixelSize: pixels) else { throw TrayError.cannotRead(image.name) }
        let format = image.writableFormat
        let output = OutputNaming.uniqueURL(base: naming.resized(image.baseName, width: resized.width, height: resized.height),
                                            ext: format.fileExtension, in: directory)
        var properties = image.metadataForOrientedPixels()
        if format.isLossy { properties[kCGImageDestinationLossyCompressionQuality] = quality }
        try write(to: output, as: format) { CGImageDestinationAddImage($0, resized, properties as CFDictionary) }
        return output
    }

    /// The same image with no EXIF, GPS, TIFF or maker data (orientation baked into the pixels).
    static func stripMetadata(_ input: URL, quality: Double, into directory: URL, naming: OutputNaming) throws -> URL {
        let image = try ImageFile(input)
        guard let pixels = image.oriented(maxPixelSize: max(image.orientedWidth, image.orientedHeight)) else {
            throw TrayError.cannotRead(image.name)
        }
        let format = image.writableFormat
        let output = OutputNaming.uniqueURL(base: naming.withoutMetadata(image.baseName), ext: format.fileExtension, in: directory)
        let properties: [CFString: Any] = format.isLossy ? [kCGImageDestinationLossyCompressionQuality: quality] : [:]
        try write(to: output, as: format) { CGImageDestinationAddImage($0, pixels, properties as CFDictionary) }
        return output
    }

    /// The longer side a resize produces (pure; also used by the editor's name preview).
    static func targetLongestSide(longest: Int, target: TrayResize, defaultMaxDimension: Int) -> Int {
        switch target {
        case .scale(let percent):
            return max(Int((Double(longest) * Double(min(max(percent, 1), 100)) / 100).rounded()), 1)
        case .maxDimension(let pixels):
            return max(min(pixels > 0 ? pixels : defaultMaxDimension, longest), 1)
        }
    }

    /// Width × height as displayed (orientation applied), or nil for a non-image.
    static func orientedPixelSize(of url: URL) -> (width: Int, height: Int)? {
        guard let image = try? ImageFile(url) else { return nil }
        return (image.orientedWidth, image.orientedHeight)
    }

    // MARK: Writing

    private static func reencode(_ image: ImageFile, as format: TrayImageFormat, quality: Double, to output: URL) throws {
        var options: [CFString: Any] = [:]
        if format.isLossy { options[kCGImageDestinationLossyCompressionQuality] = quality }
        if image.hasAlpha && !format.supportsAlpha {
            guard let raw = image.rawImage(), let flat = flattenedOnWhite(raw) else { throw TrayError.cannotRead(image.name) }
            var properties = image.properties
            properties.merge(options) { _, new in new }
            try write(to: output, as: format) { CGImageDestinationAddImage($0, flat, properties as CFDictionary) }
        } else {
            try write(to: output, as: format) { CGImageDestinationAddImageFromSource($0, image.source, 0, options as CFDictionary) }
        }
    }

    private static func write(to url: URL, as format: TrayImageFormat, add: (CGImageDestination) -> Void) throws {
        guard canWrite(format) else { throw TrayError.formatUnavailable(format.displayName) }
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, format.type.identifier as CFString, 1, nil) else {
            throw TrayError.cannotWrite
        }
        add(destination)
        guard CGImageDestinationFinalize(destination) else {
            try? FileManager.default.removeItem(at: url)
            throw TrayError.cannotWrite
        }
    }

    private static func flattenedOnWhite(_ image: CGImage) -> CGImage? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(rect)
        context.draw(image, in: rect)
        return context.makeImage()
    }

    static func fileSize(_ url: URL) -> Int64 {
        Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
    }
}

/// An opened image file: its source, type, metadata and displayed size.
nonisolated struct ImageFile {
    let url: URL
    let source: CGImageSource
    let type: UTType
    let properties: [CFString: Any]
    let pixelWidth: Int
    let pixelHeight: Int
    let orientation: Int
    let hasAlpha: Bool

    init(_ url: URL) throws {
        let name = url.lastPathComponent
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(source) > 0,
              let identifier = CGImageSourceGetType(source) as String?,
              let type = UTType(identifier), type.conforms(to: .image),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            throw TrayError.unsupportedFile(name)
        }
        self.url = url
        self.source = source
        self.type = type
        self.properties = properties
        pixelWidth = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue ?? 0
        pixelHeight = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue ?? 0
        orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        hasAlpha = (properties[kCGImagePropertyHasAlpha] as? NSNumber)?.boolValue ?? false
        guard pixelWidth > 0, pixelHeight > 0 else { throw TrayError.unsupportedFile(name) }
    }

    var name: String { url.lastPathComponent }
    var baseName: String { url.deletingPathExtension().lastPathComponent }
    var format: TrayImageFormat? { TrayImageFormat(type: type) }
    /// EXIF orientations 5–8 rotate by 90°.
    private var isQuarterTurned: Bool { (5...8).contains(orientation) }
    var orientedWidth: Int { isQuarterTurned ? pixelHeight : pixelWidth }
    var orientedHeight: Int { isQuarterTurned ? pixelWidth : pixelHeight }

    /// The source format if ImageIO can write it; otherwise PNG for transparency, JPEG for the rest.
    var writableFormat: TrayImageFormat {
        if let format, ImageSteps.canWrite(format) { return format }
        return hasAlpha ? .png : .jpeg
    }

    /// Decoded pixels as stored (orientation not applied).
    func rawImage() -> CGImage? { CGImageSourceCreateImageAtIndex(source, 0, nil) }

    /// Decoded pixels with the orientation applied, the longer side at most `maxPixelSize`.
    func oriented(maxPixelSize: Int) -> CGImage? {
        CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: max(maxPixelSize, 1),
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
        ] as CFDictionary)
    }

    /// The source's metadata for pixels that already have the orientation applied: orientation 1, no stale sizes.
    func metadataForOrientedPixels() -> [CFString: Any] {
        var metadata = properties
        metadata[kCGImagePropertyOrientation] = 1
        metadata[kCGImagePropertyPixelWidth] = nil
        metadata[kCGImagePropertyPixelHeight] = nil
        if var tiff = metadata[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
            tiff[kCGImagePropertyTIFFOrientation] = 1
            metadata[kCGImagePropertyTIFFDictionary] = tiff
        }
        if var exif = metadata[kCGImagePropertyExifDictionary] as? [CFString: Any] {
            exif[kCGImagePropertyExifPixelXDimension] = nil
            exif[kCGImagePropertyExifPixelYDimension] = nil
            metadata[kCGImagePropertyExifDictionary] = exif
        }
        return metadata
    }
}
