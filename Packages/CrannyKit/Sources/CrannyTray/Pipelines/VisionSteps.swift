// CrannyTray/Pipelines/VisionSteps.swift — Remove background (`VNGenerateForegroundInstanceMaskRequest`, macOS 14)
// and Copy text (`VNRecognizeTextRequest`), on-device only (ARCHITECTURE.md §7.8, R3 §8). Runs in the pipeline's
// background context. One Core Image context serves every image (each new one would set up its own Metal queue and
// caches); it is made on the first Remove background, never at launch.
import CoreImage
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import Vision

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

    /// Text recognized in each image, in reading order; images are separated by a blank line.
    static func recognizeText(in inputs: [URL]) throws -> String {
        var blocks: [String] = []
        for input in inputs {
            try Task.checkCancellation()
            let image = try ImageFile(input)
            guard let pixels = image.oriented(maxPixelSize: max(image.orientedWidth, image.orientedHeight)) else {
                throw TrayError.cannotRead(image.name)
            }
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.automaticallyDetectsLanguage = true
            do { try VNImageRequestHandler(cgImage: pixels, options: [:]).perform([request]) } catch { throw TrayError.noText }
            let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
            if !lines.isEmpty { blocks.append(lines.joined(separator: "\n")) }
        }
        guard !blocks.isEmpty else { throw TrayError.noText }
        return blocks.joined(separator: "\n\n")
    }
}
