// CrannyTray/Pipelines/VisionSteps.swift — Remove background (`VNGenerateForegroundInstanceMaskRequest`, macOS 14)
// and Copy text (`VNRecognizeTextRequest`), on-device only (ARCHITECTURE.md §7.8, R3 §8). Runs in the pipeline's
// background context. One Core Image context serves every image (each new one would set up its own Metal queue and
// caches); it is made on the first Remove background, never at launch.
import CoreImage
import CoreGraphics
import CrannyCore
import Foundation
import ImageIO
import os
import UniformTypeIdentifiers
import Vision

private nonisolated let log = Log.logger(.pipelines)

nonisolated enum VisionSteps {
    /// Shared by every Remove background (`CIContext` is thread-safe); intermediates are not kept between images.
    private static let context = CIContext(options: [.cacheIntermediates: false])

    /// The subject on a transparent background, as PNG in `directory`.
    static func removeBackground(_ input: URL, into directory: URL, naming: OutputNaming) throws -> URL {
        let image = try ImageFile(input)
        guard let pixels = image.oriented(maxPixelSize: max(image.orientedWidth, image.orientedHeight)) else {
            throw TrayError.cannotRead(image.name)
        }
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: pixels, options: [:])
        do { try handler.perform([request]) } catch { throw TrayError.noSubject }
        guard let observation = request.results?.first, !observation.allInstances.isEmpty,
              let buffer = try? observation.generateMaskedImage(ofInstances: observation.allInstances, from: handler,
                                                                croppedToInstancesExtent: false) else {
            throw TrayError.noSubject
        }
        let ciImage = CIImage(cvPixelBuffer: buffer)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let masked = context.createCGImage(ciImage, from: ciImage.extent, format: .RGBA8, colorSpace: space) else {
            throw TrayError.cannotWrite
        }
        try Task.checkCancellation()
        let output = OutputNaming.uniqueURL(base: naming.withoutBackground(image.baseName), ext: "png", in: directory)
        guard let destination = CGImageDestinationCreateWithURL(output as CFURL, TrayImageFormat.png.type.identifier as CFString, 1, nil) else {
            throw TrayError.cannotWrite
        }
        CGImageDestinationAddImage(destination, masked, nil)
        guard CGImageDestinationFinalize(destination) else {
            try? FileManager.default.removeItem(at: output)
            throw TrayError.cannotWrite
        }
        return output
    }

    /// Text recognized in each image, in reading order; images are separated by a blank line. Reads with `.accurate`
    /// (`level: .fast` starts with the fallback, for tests); when that request fails (its neural model cannot be
    /// loaded: a Mac without a Neural Engine, such as GitHub's macOS 27 virtual machines, or a failed model compile on
    /// macOS 27), this image and the rest are read with `.fast`, which needs no such model but knows fewer languages.
    /// Finding nothing is no failure: no text is there.
    static func recognizeText(in inputs: [URL], level: VNRequestTextRecognitionLevel = .accurate) throws -> String {
        var level = level
        var blocks: [String] = []
        for input in inputs {
            try Task.checkCancellation()
            let image = try ImageFile(input)
            guard let pixels = image.oriented(maxPixelSize: max(image.orientedWidth, image.orientedHeight)) else {
                throw TrayError.cannotRead(image.name)
            }
            let lines: [String]
            do { lines = try recognizeLines(in: pixels, level: level) } catch where level == .accurate {
                log.info("accurate text recognition failed (\(TrayLogCode.of(error), privacy: .public)); reading with .fast")
                level = .fast
                try Task.checkCancellation()
                do { lines = try recognizeLines(in: pixels, level: .fast) } catch { throw TrayError.noText }
            } catch {
                throw TrayError.noText
            }
            if !lines.isEmpty { blocks.append(lines.joined(separator: "\n")) }
        }
        guard !blocks.isEmpty else { throw TrayError.noText }
        return blocks.joined(separator: "\n\n")
    }

    /// Text reads take turns. Reads at the same time have hung GitHub's 3-core virtual Macs (Vision's text detector
    /// waiting on work of its own while every caller's thread waited on its queue); a read takes ≈ 0.1 s on a Mac.
    private static let reading = NSLock()

    private static func recognizeLines(in pixels: CGImage, level: VNRequestTextRecognitionLevel) throws -> [String] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = level
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true
        try reading.withLock { try VNImageRequestHandler(cgImage: pixels, options: [:]).perform([request]) }
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
    }
}
