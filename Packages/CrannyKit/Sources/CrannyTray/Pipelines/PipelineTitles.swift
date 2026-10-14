// CrannyTray/Pipelines/PipelineTitles.swift — the localized words for pipelines and their steps (chips, catch zones,
// the pipeline editor, VoiceOver). Built-ins are named here; user pipelines carry the user's own name.
import Foundation

nonisolated enum PipelineTitles {
    /// The pipeline's name: the user's, or its single step's title for a built-in.
    static func title(_ pipeline: PipelineDefinition, maxDimension: Int) -> String {
        if let name = pipeline.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty { return name }
        if pipeline.isUserPipeline {
            return String(localized: "Untitled pipeline", bundle: .module, comment: "Settings ▸ Tray: name of a user pipeline that has none")
        }
        return pipeline.steps.first.map { step($0, maxDimension: maxDimension) } ?? ""
    }

    /// A step with its parameters ("Convert to PNG", "Resize to 50 %", "Resize to 1600 px").
    static func step(_ step: PipelineStep, maxDimension: Int) -> String {
        switch step {
        case .compress:
            return String(localized: "Compress", bundle: .module, comment: "Tray pipeline: compress images (chip, drop zone, editor step)")
        case .convert(let format):
            return String(localized: "Convert to \(format.displayName)", bundle: .module, comment: "Tray pipeline: convert images; the argument is a format name such as PNG")
        case .resize(.scale(let percent)):
            let value = (Double(percent) / 100).formatted(.percent)
            return String(localized: "Resize to \(value)", bundle: .module, comment: "Tray pipeline: resize images by a percentage, \"Resize to 50 %\"")
        case .resize(.maxDimension(let pixels)):
            let value = String(pixels > 0 ? pixels : maxDimension)        // pixel sizes are never grouped ("1600 px")
            return String(localized: "Resize to \(value) px", bundle: .module, comment: "Tray pipeline: resize images so the longer side is at most N pixels; the argument is a number of pixels")
        case .stripMetadata:
            return String(localized: "Strip metadata", bundle: .module, comment: "Tray pipeline: remove location and camera data from images")
        case .removeBackground:
            return String(localized: "Remove background", bundle: .module, comment: "Tray pipeline: cut the subject out of a photo")
        case .makePDF:
            return String(localized: "Make PDF", bundle: .module, comment: "Tray pipeline: combine images and PDFs into one PDF")
        case .compressVideo:
            return String(localized: "Compress video", bundle: .module, comment: "Tray pipeline: make a video file smaller")
        case .zip:
            return String(localized: "Zip", bundle: .module, comment: "Tray pipeline: make a zip archive")
        case .unzip:
            return String(localized: "Unzip", bundle: .module, comment: "Tray pipeline: extract a zip archive")
        case .copyPaths:
            return String(localized: "Copy paths", bundle: .module, comment: "Tray pipeline: copy the files' paths as text")
        case .copyText:
            return String(localized: "Copy text", bundle: .module, comment: "Tray pipeline: recognize the text in images and copy it")
        case .reveal:
            return String(localized: "Reveal in Finder", bundle: .module, comment: "Tray action and pipeline step: show the files in Finder")
        }
    }

    /// The step without parameters (the editor's "Add step" menu).
    static func kind(_ step: PipelineStep, maxDimension: Int) -> String {
        switch step {
        case .convert:
            String(localized: "Convert", bundle: .module, comment: "Tray pipeline: convert images (menu chip and editor step, before choosing a format)")
        case .resize:
            String(localized: "Resize", bundle: .module, comment: "Tray pipeline: resize images (menu chip and editor step, before choosing a size)")
        default:
            Self.step(step, maxDimension: maxDimension)
        }
    }

    /// What a step needs, for the editor's warning ("needs images").
    static func content(_ content: PipelineContent) -> String {
        switch content {
        case .images: String(localized: "images", bundle: .module, comment: "Settings ▸ Tray ▸ pipeline editor: kind of file a step needs or makes")
        case .movies: String(localized: "videos", bundle: .module, comment: "Settings ▸ Tray ▸ pipeline editor: kind of file a step needs or makes")
        case .archives: String(localized: "zip archives", bundle: .module, comment: "Settings ▸ Tray ▸ pipeline editor: kind of file a step needs or makes")
        case .pdf: String(localized: "PDFs", bundle: .module, comment: "Settings ▸ Tray ▸ pipeline editor: kind of file a step needs or makes")
        case .printable: String(localized: "images or PDFs", bundle: .module, comment: "Settings ▸ Tray ▸ pipeline editor: kind of file a step needs or makes")
        case .any: String(localized: "any files", bundle: .module, comment: "Settings ▸ Tray ▸ pipeline editor: kind of file a step needs or makes")
        }
    }

    /// "Needs images, but the step before makes zip archives."
    static func problem(_ problem: PipelineProblem) -> String {
        let needs = content(problem.needs), gets = content(problem.gets)
        return String(localized: "Needs \(needs), but the step before makes \(gets).", bundle: .module,
                      comment: "Settings ▸ Tray ▸ pipeline editor: warning under a step that cannot run; arguments are kinds of files")
    }
}
