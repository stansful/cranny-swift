// CrannyTray/Pipelines/BuiltinPipelines.swift — the built-in actions of DESIGN.md §8.2 as one-step pipelines, so
// chips, catch zones, pins and user chains share one code path. Ids are persisted in `TraySettings.pinnedPipelines`:
// never rename one.
import Foundation
import UniformTypeIdentifiers

nonisolated enum BuiltinPipelines {
    static let compress = builtin("compress", "photo.badge.arrow.down", .compress)
    static let resizeHalf = builtin("resize.half", "square.resize", .resize(to: .scale(percent: 50)))
    /// "Max N px" with N = `TraySettings.maxDimension`.
    static let resizeMax = builtin("resize.max", "square.resize", .resize(to: .maxDimension(pixels: 0)))
    static let resize2048 = builtin("resize.2048", "square.resize", .resize(to: .maxDimension(pixels: 2048)))
    static let stripMetadata = builtin("stripMetadata", "eye.slash", .stripMetadata)
    static let removeBackground = builtin("removeBackground", "scissors", .removeBackground)
    static let copyText = builtin("copyText", "text.viewfinder", .copyText)
    static let makePDF = builtin("makePDF", "doc.richtext", .makePDF)
    static let compressVideo = builtin("compressVideo", "film", .compressVideo)
    static let zip = builtin("zip", "doc.zipper", .zip)
    static let unzip = builtin("unzip", "archivebox", .unzip)
    static let copyPaths = builtin("copyPaths", "link", .copyPaths)
    static let reveal = builtin("reveal", "folder", .reveal)

    static func convert(_ format: TrayImageFormat) -> PipelineDefinition {
        builtin("convert.\(format.rawValue)", "arrow.triangle.2.circlepath", .convert(format: format))
    }

    /// Every built-in that can be pinned as a drop zone, in Settings order (Reveal is a chip/menu action only).
    static var pinnable: [PipelineDefinition] {
        [compress] + ImageSteps.writableFormats.map(convert) + [resizeHalf, resizeMax, resize2048, stripMetadata,
            removeBackground, copyText, makePDF, compressVideo, zip, unzip, copyPaths]
    }

    /// Built-ins first, then the user's chains.
    static func all(userPipelines: [PipelineDefinition]) -> [PipelineDefinition] { pinnable + [reveal] + userPipelines }

    /// The pipeline with `id` among the built-ins and `userPipelines`.
    static func definition(_ id: String, userPipelines: [PipelineDefinition]) -> PipelineDefinition? {
        all(userPipelines: userPipelines).first { $0.id == id }
    }

    /// Pinned pipelines that can take every one of `types`, at most `TraySettings.maxPinnedPipelines`
    /// (DESIGN.md §8.3: the catch state shows Keep and AirDrop, then up to 3 pinned pipelines that accept the drag).
    /// A drag that only says "file URL" (no content types yet) is offered the pipelines that take any file.
    static func catchZones(pinned: [String], userPipelines: [PipelineDefinition], types: [UTType]) -> [PipelineDefinition] {
        let resolved = pinned.compactMap { definition($0, userPipelines: userPipelines) }
        return Array(resolved.filter { $0.accepts(types.isEmpty ? [.item] : types) }.prefix(TraySettings.maxPinnedPipelines))
    }

    private static func builtin(_ id: String, _ symbol: String, _ step: PipelineStep) -> PipelineDefinition {
        PipelineDefinition(id: "builtin.\(id)", name: nil, symbol: symbol, steps: [step])
    }
}
