// Pipeline steps on temporary files (ARCHITECTURE.md §10.9 acceptance): formats from
// `CGImageDestinationCopyTypeIdentifiers()`, zip/unzip round trip, resize keeps orientation, cancellation.
import AVFoundation
import CoreGraphics
import CrannyCore
import Foundation
import ImageIO
import PDFKit
import Testing
import UniformTypeIdentifiers
import Vision
@testable import CrannyTray

@Suite struct ImageStepTests {
    let naming = OutputNaming.english

    @Test func writableFormatsComeFromImageIO() {
        let reported = Set((CGImageDestinationCopyTypeIdentifiers() as? [String]) ?? [])
        #expect(ImageSteps.writableTypeIdentifiers == reported)
        for format in TrayImageFormat.allCases {
            #expect(ImageSteps.canWrite(format) == reported.contains(format.type.identifier))
        }
        #expect(ImageSteps.canWrite(.jpeg) && ImageSteps.canWrite(.png))
    }

    @Test func compressKeepsSizeAndShrinksTheFile() throws {
        let folder = Fixtures.folder("compress")
        let input = Fixtures.image("photo.png", in: folder, width: 640, height: 480)
        let output = try ImageSteps.compress(input, quality: 0.8, into: folder, naming: naming)
        #expect(output.lastPathComponent == "photo (compressed).jpg")
        #expect(Fixtures.type(of: output) == .jpeg)
        #expect(ImageSteps.orientedPixelSize(of: output)?.width == 640)
        #expect(Fixtures.size(output) < Fixtures.size(input))
        #expect(FileManager.default.fileExists(atPath: input.path))         // never touches the input
    }

    @Test func compressKeepsTransparencyAsHEIC() throws {
        guard ImageSteps.canWrite(.heic) else { return }
        let folder = Fixtures.folder("compress-alpha")
        let input = Fixtures.image("logo.png", in: folder, width: 320, height: 320, alpha: true)
        let output = try ImageSteps.compress(input, quality: 0.8, into: folder, naming: naming)
        #expect(output.pathExtension == "heic")
    }

    @Test func compressRefusesToGrowAFile() throws {
        let folder = Fixtures.folder("compress-small")
        let input = Fixtures.image("tiny.jpg", in: folder, width: 200, height: 150, type: .jpeg, quality: 0.2)
        #expect(throws: TrayError.notSmaller) { try ImageSteps.compress(input, quality: 1.0, into: folder, naming: naming) }
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        #expect(leftovers == ["tiny.jpg"])
    }

    @Test(arguments: TrayImageFormat.allCases)
    func convertWritesEveryWritableFormat(_ format: TrayImageFormat) throws {
        let folder = Fixtures.folder("convert")
        let input = Fixtures.image("shot.png", in: folder, alpha: true)
        guard ImageSteps.canWrite(format) else {
            #expect(throws: TrayError.formatUnavailable(format.displayName)) {
                try ImageSteps.convert(input, to: format, quality: 0.8, into: folder)
            }
            return
        }
        let output = try ImageSteps.convert(input, to: format, quality: 0.8, into: folder)
        #expect(output.pathExtension == format.fileExtension)
        #expect(Fixtures.type(of: output)?.conforms(to: format.type) == true)
        #expect(ImageSteps.orientedPixelSize(of: output)?.width == 400)
        if !format.supportsAlpha {
            #expect((Fixtures.properties(of: output)[kCGImagePropertyHasAlpha] as? Bool) != true)
        }
    }

    @Test func resizeByPercentAndToMaximum() throws {
        let folder = Fixtures.folder("resize")
        let input = Fixtures.image("hero.png", in: folder, width: 800, height: 400)
        let half = try ImageSteps.resize(input, to: .scale(percent: 50), defaultMaxDimension: 1600, quality: 0.8, into: folder, naming: naming)
        #expect(half.lastPathComponent == "hero 400×200.png")
        let max = try ImageSteps.resize(input, to: .maxDimension(pixels: 0), defaultMaxDimension: 200, quality: 0.8, into: folder, naming: naming)
        #expect(ImageSteps.orientedPixelSize(of: max).map { [$0.width, $0.height] } == [200, 100])
        // Never enlarges.
        let same = try ImageSteps.resize(input, to: .maxDimension(pixels: 4000), defaultMaxDimension: 200, quality: 0.8, into: folder, naming: naming)
        #expect(ImageSteps.orientedPixelSize(of: same)?.width == 800)
        #expect(ImageSteps.targetLongestSide(longest: 1000, target: .scale(percent: 0), defaultMaxDimension: 1) == 10)
    }

    @Test func resizeKeepsOrientation() throws {
        let folder = Fixtures.folder("orientation")
        // Stored 400 × 300 with EXIF orientation 6: displayed as 300 × 400 (portrait).
        let input = Fixtures.image("portrait.jpg", in: folder, width: 400, height: 300, type: .jpeg, orientation: 6)
        #expect(ImageSteps.orientedPixelSize(of: input).map { [$0.width, $0.height] } == [300, 400])
        let output = try ImageSteps.resize(input, to: .maxDimension(pixels: 200), defaultMaxDimension: 1600, quality: 0.8,
                                           into: folder, naming: naming)
        let properties = Fixtures.properties(of: output)
        #expect((properties[kCGImagePropertyPixelWidth] as? Int) == 150)
        #expect((properties[kCGImagePropertyPixelHeight] as? Int) == 200)
        #expect(((properties[kCGImagePropertyOrientation] as? Int) ?? 1) == 1)
        #expect(output.lastPathComponent == "portrait 150×200.jpg")
    }

    @Test func stripMetadataRemovesLocation() throws {
        let folder = Fixtures.folder("strip")
        let input = Fixtures.image("trip.jpg", in: folder, type: .jpeg, orientation: 6, gps: true)
        #expect(Fixtures.properties(of: input)[kCGImagePropertyGPSDictionary] != nil)
        let output = try ImageSteps.stripMetadata(input, quality: 0.8, into: folder, naming: naming)
        let properties = Fixtures.properties(of: output)
        #expect(properties[kCGImagePropertyGPSDictionary] == nil)
        #expect(((properties[kCGImagePropertyOrientation] as? Int) ?? 1) == 1)
        #expect((properties[kCGImagePropertyPixelWidth] as? Int) == 300)        // orientation baked in
        #expect(output.lastPathComponent == "trip (no metadata).jpg")
    }

    @Test func nonImagesAreRejected() {
        let folder = Fixtures.folder("reject")
        let text = Fixtures.text("notes.txt", in: folder)
        #expect(throws: TrayError.unsupportedFile("notes.txt")) { try ImageSteps.compress(text, quality: 0.8, into: folder, naming: naming) }
        #expect(ImageSteps.orientedPixelSize(of: text) == nil)
    }
}

@Suite struct ArchiveStepTests {
    @Test func zipAndUnzipOneFile() async throws {
        let folder = Fixtures.folder("zip-one")
        let input = Fixtures.text("Brief.txt", in: folder, contents: "brief\n")
        let out = Fixtures.folder("zip-one-out")
        let zip = try await ArchiveSteps.zip([input], baseName: "Brief", into: out, scratch: Fixtures.folder("scratch"))
        #expect(zip.lastPathComponent == "Brief.zip")
        let restored = try await ArchiveSteps.unzip(zip, into: Fixtures.folder("unzip-one"), scratch: Fixtures.folder("scratch"))
        #expect(restored.lastPathComponent == "Brief.txt")
        #expect(try Data(contentsOf: restored) == Data("brief\n".utf8))
    }

    @Test func zipSeveralIntoOneFolder() async throws {
        let folder = Fixtures.folder("zip-many")
        let a = Fixtures.text("a.txt", in: folder, contents: "A")
        let b = Fixtures.image("b.png", in: folder, width: 40, height: 40)
        let zip = try await ArchiveSteps.zip([a, b], baseName: "Archive 2026-10-14", into: Fixtures.folder("out"), scratch: Fixtures.folder("scratch"))
        let restored = try await ArchiveSteps.unzip(zip, into: Fixtures.folder("unzip-many"), scratch: Fixtures.folder("scratch"))
        #expect(restored.lastPathComponent == "Archive 2026-10-14")
        let names = try FileManager.default.contentsOfDirectory(atPath: restored.path).sorted()
        #expect(names == ["a.txt", "b.png"])
        #expect(try Data(contentsOf: restored.appending(path: "b.png")) == Data(contentsOf: b))
    }

    @Test func unzipOfGarbageFails() async throws {
        let folder = Fixtures.folder("bad-zip")
        let bad = Fixtures.text("bad.zip", in: folder, contents: "not a zip")
        await #expect(throws: TrayError.unarchiveFailed) {
            try await ArchiveSteps.unzip(bad, into: Fixtures.folder("bad-out"), scratch: Fixtures.folder("scratch"))
        }
    }
}

@Suite struct DocumentStepTests {
    @Test func imagesAndPDFsBecomeOnePDF() throws {
        let folder = Fixtures.folder("pdf")
        let a = Fixtures.image("page1.png", in: folder, width: 300, height: 400)
        let b = Fixtures.image("page2.jpg", in: folder, width: 400, height: 300, type: .jpeg)
        let first = try PDFSteps.makePDF([a, b], into: folder)
        #expect(first.lastPathComponent == "page1.pdf")
        #expect(PDFDocument(url: first)?.pageCount == 2)
        let merged = try PDFSteps.makePDF([first, a], into: folder)
        #expect(merged.lastPathComponent == "page1 2.pdf")
        #expect(PDFDocument(url: merged)?.pageCount == 3)
        #expect(throws: TrayError.unsupportedFile("notes.txt")) {
            try PDFSteps.makePDF([Fixtures.text("notes.txt", in: folder)], into: folder)
        }
    }

    @Test func removeBackgroundNeedsASubject() {
        let folder = Fixtures.folder("subject")
        let flat = Fixtures.image("flat.png", in: folder, width: 200, height: 200, noise: false)
        do {
            let output = try VisionSteps.removeBackground(flat, into: folder, naming: .english)
            #expect(output.pathExtension == "png")                 // Vision found something: a PNG was written
        } catch {
            #expect(error as? TrayError == .noSubject)
        }
    }

    @Test func compressVideoWritesASmallerMP4() async throws {
        let folder = Fixtures.folder("video")
        let movie = try await MovieFixture.write(to: folder.appending(path: "Clip.mov"), side: 320, bitRate: 40_000_000, noise: true)
        let output = try await VideoSteps.compressVideo(movie, into: folder, naming: .english)
        #expect(output.lastPathComponent == "Clip (compressed).mp4")
        #expect(Fixtures.size(output) < Fixtures.size(movie))
        let duration = try await AVURLAsset(url: output).load(.duration)
        #expect(duration.seconds > 0.5)
    }

    @Test func compressVideoNeverHandsBackABiggerFile() async throws {
        let folder = Fixtures.folder("video-small")
        let movie = try await MovieFixture.write(to: folder.appending(path: "Tiny.mov"), side: 64, bitRate: 8_000, noise: false)
        await #expect(throws: TrayError.notSmaller) { try await VideoSteps.compressVideo(movie, into: folder, naming: .english) }
        #expect(!FileManager.default.fileExists(atPath: folder.appending(path: "Tiny (compressed).mp4").path))
    }

    @Test func compressVideoRejectsOtherFiles() async {
        let folder = Fixtures.folder("video-bad")
        let text = Fixtures.text("notes.txt", in: folder)
        await #expect(throws: TrayError.self) { try await VideoSteps.compressVideo(text, into: folder, naming: .english) }
    }
}

/// Copy text (`VisionSteps.recognizeText`). Serialized like the app's reads, which take turns: reads at the same time
/// have hung GitHub's 3-core virtual Macs.
@Suite(.serialized) struct CopyTextTests {
    /// Reads `.accurate` where its model loads, `.fast` where it cannot (CI's virtual Macs have no Neural Engine), so
    /// the test reads text on every Mac. The blank image is plain white: `.fast` reads a letter into a coloured box.
    @Test func copyTextRecognizesText() throws {
        let folder = Fixtures.folder("ocr")
        let image = Fixtures.textImage("CRANNY 2026", in: folder)
        let text = try VisionSteps.recognizeText(in: [image])
        #expect(text.uppercased().contains("CRANNY"))
        let blank = Fixtures.textImage("", named: "blank.png", in: folder)
        #expect(throws: TrayError.noText) { try VisionSteps.recognizeText(in: [blank]) }
    }

    /// Where a bare `.accurate` request loads its model, Copy text reads with `.accurate`: only it reads Cyrillic
    /// (`.fast` reads Latin look-alikes), so an option that broke `.accurate` on every Mac cannot hide behind the
    /// fallback. On a Mac without the model (CI) the fallback is the right reading, and there is nothing to check.
    @Test func copyTextReadsRussianWithTheAccurateModel() throws {
        let folder = Fixtures.folder("ocr-ru")
        let image = Fixtures.textImage("ПРИВЕТ МИР", in: folder)
        let text = try VisionSteps.recognizeText(in: [image])
        guard Self.accurateModelLoads(image) else { return }
        #expect(text.uppercased().contains("ПРИВЕТ"), "read “\(text)”")
    }

    /// The reading Copy text falls back to, on every Mac (where `.accurate` loads, the tests above never reach it).
    @Test func copyTextAlsoReadsWithTheFastLevel() throws {
        let folder = Fixtures.folder("ocr-fast")
        let image = Fixtures.textImage("CRANNY 2026", in: folder)
        let text = try VisionSteps.recognizeText(in: [image], level: .fast)
        #expect(text.uppercased().contains("CRANNY"))
        let blank = Fixtures.textImage("", named: "blank.png", in: folder)
        #expect(throws: TrayError.noText) { try VisionSteps.recognizeText(in: [blank], level: .fast) }
    }

    /// A bare `.accurate` request, with none of Copy text's options, performs on `image` on this Mac.
    static func accurateModelLoads(_ image: URL) -> Bool {
        guard let source = CGImageSourceCreateWithURL(image as CFURL, nil),
              let pixels = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return false }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        do { try VNImageRequestHandler(cgImage: pixels, options: [:]).perform([request]) } catch { return false }
        return true
    }
}

/// A one-second square H.264 movie written with AVAssetWriter: flat grey frames, or noise at a high bit rate (a file
/// that compresses well).
enum MovieFixture {
    static func write(to url: URL, side: Int = 128, bitRate: Int = 2_000_000, noise: Bool = false) async throws -> URL {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: side, AVVideoHeightKey: side,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: bitRate],
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: side, kCVPixelBufferHeightKey as String: side,
        ])
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        var seed: UInt32 = 7
        for frame in 0..<30 {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(5)) }
            var buffer: CVPixelBuffer?
            CVPixelBufferCreate(nil, side, side, kCVPixelFormatType_32BGRA, nil, &buffer)
            guard let buffer else { continue }
            CVPixelBufferLockBaseAddress(buffer, [])
            if let base = CVPixelBufferGetBaseAddress(buffer) {
                let count = CVPixelBufferGetDataSize(buffer)
                if noise {
                    let bytes = base.bindMemory(to: UInt8.self, capacity: count)
                    for i in 0..<count {
                        seed = seed &* 1_664_525 &+ 1_013_904_223
                        bytes[i] = UInt8(truncatingIfNeeded: seed >> 24)
                    }
                } else {
                    memset(base, Int32(frame * 8), count)
                }
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])
            adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: 30))
        }
        input.markAsFinished()
        await writer.finishWriting()
        return url
    }
}

@Suite struct RunnerTests {
    @Test func chainsComposeAndReportProgress() async throws {
        let folder = Fixtures.folder("chain")
        let input = Fixtures.image("hero.png", in: folder, width: 800, height: 600)
        var options = PipelineOptions()
        options.maxDimension = 400
        let progress = ProgressLog()
        let result = try await PipelineRunner.run([.resize(to: .maxDimension(pixels: 0)), .convert(format: .jpeg), .copyPaths],
                                                  inputs: [input], options: options, workDirectory: Fixtures.folder("work")) {
            progress.add($0)
        }
        #expect(result.files.map(\.lastPathComponent) == ["hero 400×300.jpg"])
        #expect(result.copiesPaths && !result.reveals && result.text == nil)
        #expect(progress.values.last == 1)
        #expect(progress.values == progress.values.sorted())
    }

    @Test func passThroughChainsWriteNothing() async throws {
        let folder = Fixtures.folder("pass")
        let input = Fixtures.text("a.txt", in: folder)
        let result = try await PipelineRunner.run([.copyPaths, .reveal], inputs: [input], options: PipelineOptions(),
                                                  workDirectory: Fixtures.folder("work")) { _ in }
        #expect(result.files.isEmpty && result.copiesPaths && result.reveals)
    }

    @Test func zipNamingIsUsed() async throws {
        let folder = Fixtures.folder("zipname")
        let a = Fixtures.text("Brief.txt", in: folder), b = Fixtures.text("b.txt", in: folder)
        var options = PipelineOptions()
        options.zipNaming = .firstItem
        let first = try await PipelineRunner.run([.zip], inputs: [a, b], options: options, workDirectory: Fixtures.folder("work")) { _ in }
        #expect(first.files.map(\.lastPathComponent) == ["Brief.zip"])
        options.zipNaming = .dated
        let dated = try await PipelineRunner.run([.zip], inputs: [a], options: options, workDirectory: Fixtures.folder("work")) { _ in }
        #expect(dated.files.first?.lastPathComponent.hasPrefix("Archive ") == true)
    }

    @Test func cancellationStopsTheRun() async {
        let folder = Fixtures.folder("cancel")
        let inputs = (0..<6).map { Fixtures.image("p\($0).png", in: folder, width: 600, height: 400) }
        let work = Fixtures.folder("work")
        let task = Task {
            try await PipelineRunner.run([.compress, .resize(to: .scale(percent: 50))], inputs: inputs, options: PipelineOptions(),
                                         workDirectory: work) { _ in }
        }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test func failuresSurfaceAsTrayErrors() async {
        let folder = Fixtures.folder("fail")
        let text = Fixtures.text("notes.txt", in: folder)
        await #expect(throws: TrayError.unsupportedFile("notes.txt")) {
            try await PipelineRunner.run([.compress], inputs: [text], options: PipelineOptions(), workDirectory: Fixtures.folder("work")) { _ in }
        }
        let empty = try? await PipelineRunner.run([], inputs: [text], options: PipelineOptions(), workDirectory: Fixtures.folder("work")) { _ in }
        #expect(empty == PipelineRunResult())
    }
}

/// Collects progress values from the runner's background callback.
nonisolated final class ProgressLog: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Double] = []
    func add(_ value: Double) { lock.withLock { storage.append(value) } }
    var values: [Double] { lock.withLock { storage } }
}
