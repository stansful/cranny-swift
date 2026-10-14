// CrannyTray/Pipelines/PipelineRunner.swift — runs a chain of steps off the main actor (`@concurrent`), file by file,
// reporting progress and honouring cancellation (DESIGN.md §8.2 "Running"). Intermediate and final files are written
// into a private work folder; the store moves the final ones to their destination (`OutputPlacement`) so a cancelled
// or failed run never leaves half-made files next to the user's originals.
import Foundation

/// The settings a run needs, snapshotted on the main actor.
nonisolated struct PipelineOptions: Sendable, Equatable {
    var quality: Double = 0.8
    var maxDimension: Int = 1600
    var zipNaming: TrayZipNaming = .firstItem
    var naming: OutputNaming = .english
    var date = Date()
}

/// What a finished run produced.
nonisolated struct PipelineRunResult: Sendable, Equatable {
    /// Final files, still inside the work folder. Empty when no step writes files.
    var files: [URL] = []
    /// Text for the pasteboard (Copy text).
    var text: String?
    /// The chain ends by copying the results' paths / revealing them (done after they are moved).
    var copiesPaths = false
    var reveals = false
}

nonisolated enum PipelineRunner {
    /// Runs `steps` on `inputs`. `progress` (0…1) is called from the background; hop to the main actor yourself.
    @concurrent
    static func run(_ steps: [PipelineStep], inputs: [URL], options: PipelineOptions, workDirectory: URL,
                    progress: @escaping @Sendable (Double) -> Void) async throws -> PipelineRunResult {
        guard !inputs.isEmpty, !steps.isEmpty else { return PipelineRunResult() }
        try FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)
        var current = inputs
        var result = PipelineRunResult()
        var wroteFiles = false
        for (index, step) in steps.enumerated() {
            try Task.checkCancellation()
            let stepDirectory = workDirectory.appending(path: "step-\(index)", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: stepDirectory, withIntermediateDirectories: true)
            let report: @Sendable (Double) -> Void = { fraction in
                progress((Double(index) + min(max(fraction, 0), 1)) / Double(steps.count))
            }
            switch step {
            case .copyPaths:
                result.copiesPaths = true
            case .reveal:
                result.reveals = true
            case .copyText:
                result.text = try VisionSteps.recognizeText(in: current)
            default:
                current = try await apply(step, to: current, options: options, directory: stepDirectory,
                                          scratch: workDirectory, progress: report)
                wroteFiles = true
            }
            report(1)
        }
        if wroteFiles { result.files = current }
        return result
    }

    /// One file-writing step over the current files.
    private static func apply(_ step: PipelineStep, to inputs: [URL], options: PipelineOptions, directory: URL,
                              scratch: URL, progress: @Sendable (Double) -> Void) async throws -> [URL] {
        switch step {
        case .zip:
            let base = options.naming.zipBaseName(firstItem: inputs[0].deletingPathExtension().lastPathComponent,
                                                  naming: options.zipNaming, date: options.date)
            return [try await ArchiveSteps.zip(inputs, baseName: base, into: directory, scratch: scratch)]
        case .makePDF:
            return [try PDFSteps.makePDF(inputs, into: directory)]
        default:
            var outputs: [URL] = []
            for (n, input) in inputs.enumerated() {
                try Task.checkCancellation()
                outputs.append(try await applyToFile(step, input: input, options: options, directory: directory, scratch: scratch))
                progress(Double(n + 1) / Double(inputs.count))
            }
            return outputs
        }
    }

    private static func applyToFile(_ step: PipelineStep, input: URL, options: PipelineOptions, directory: URL,
                                    scratch: URL) async throws -> URL {
        switch step {
        case .compress:
            try ImageSteps.compress(input, quality: options.quality, into: directory, naming: options.naming)
        case .convert(let format):
            try ImageSteps.convert(input, to: format, quality: options.quality, into: directory)
        case .resize(let target):
            try ImageSteps.resize(input, to: target, defaultMaxDimension: options.maxDimension, quality: options.quality,
                                  into: directory, naming: options.naming)
        case .stripMetadata:
            try ImageSteps.stripMetadata(input, quality: options.quality, into: directory, naming: options.naming)
        case .removeBackground:
            try VisionSteps.removeBackground(input, into: directory, naming: options.naming)
        case .compressVideo:
            try await VideoSteps.compressVideo(input, into: directory, naming: options.naming)
        case .unzip:
            try await ArchiveSteps.unzip(input, into: directory, scratch: scratch)
        case .zip, .makePDF, .copyPaths, .copyText, .reveal:
            input   // handled by the caller; never reached
        }
    }
}
