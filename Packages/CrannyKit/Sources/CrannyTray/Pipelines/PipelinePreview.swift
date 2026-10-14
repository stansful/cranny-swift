// CrannyTray/Pipelines/PipelinePreview.swift — "a preview of the output name" in the pipeline editor (DESIGN.md
// §11.1): what a chain would make of a typical file, computed with the same naming rules as a real run.
import Foundation

nonisolated enum PipelinePreview {
    /// A sample input for the chain's first step.
    struct Sample: Equatable, Sendable {
        var name: String
        var width: Int
        var height: Int
        var hasAlpha = false
    }

    static func sample(for content: PipelineContent) -> Sample {
        switch content {
        case .images, .printable: Sample(name: "IMG_2041.heic", width: 4032, height: 3024)
        case .movies: Sample(name: "Clip.mov", width: 1920, height: 1080)
        case .archives: Sample(name: "Assets.zip", width: 0, height: 0)
        case .pdf, .any: Sample(name: "Brief.pdf", width: 0, height: 0)
        }
    }

    /// The name of the final file (or the input's, for chains that write nothing). nil for an empty chain.
    static func outputName(of steps: [PipelineStep], sample: Sample, options: PipelineOptions) -> String? {
        guard !steps.isEmpty else { return nil }
        var base = (sample.name as NSString).deletingPathExtension
        var ext = (sample.name as NSString).pathExtension
        var width = sample.width, height = sample.height
        for step in steps {
            switch step {
            case .compress:
                ext = (ext == "heic" || sample.hasAlpha) && ImageSteps.canWrite(.heic) ? "heic" : "jpg"
                base = options.naming.compressed(base)
            case .convert(let format):
                ext = format.fileExtension
            case .resize(let target):
                let longest = max(width, height)
                let side = ImageSteps.targetLongestSide(longest: longest, target: target, defaultMaxDimension: options.maxDimension)
                let scale = longest > 0 ? Double(side) / Double(longest) : 1
                width = Int((Double(width) * scale).rounded()); height = Int((Double(height) * scale).rounded())
                base = options.naming.resized(base, width: width, height: height)
            case .stripMetadata:
                base = options.naming.withoutMetadata(base)
            case .removeBackground:
                base = options.naming.withoutBackground(base); ext = "png"
            case .makePDF:
                ext = "pdf"
            case .compressVideo:
                base = options.naming.compressed(base); ext = "mp4"
            case .zip:
                base = options.naming.zipBaseName(firstItem: base, naming: options.zipNaming, date: options.date); ext = "zip"
            case .unzip:
                ext = ""
            case .copyPaths, .copyText, .reveal:
                break
            }
        }
        return ext.isEmpty ? base : "\(base).\(ext)"
    }
}
