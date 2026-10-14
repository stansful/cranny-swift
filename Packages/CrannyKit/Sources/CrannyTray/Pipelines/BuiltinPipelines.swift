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

/// `TraySettings.pinnedPipelines` as numbered slots (Settings ▸ Tray ▸ Drop zone 1–3). An empty string is a free slot,
/// so freeing zone 1 never moves zone 2's pipeline up; trailing free slots are dropped (the default stays equal).
/// The catch view skips free slots (`BuiltinPipelines.catchZones` ignores ids it does not know).
nonisolated enum PinnedPipelineSlots {
    /// The id in `slot`, nil when free.
    static func id(in pinned: [String], slot: Int) -> String? {
        pinned.indices.contains(slot) && !pinned[slot].isEmpty ? pinned[slot] : nil
    }

    /// `pinned` with `id` in `slot` (nil frees it). A pipeline pinned in another slot leaves that slot.
    static func setting(_ id: String?, slot: Int, in pinned: [String]) -> [String] {
        var slots = Array(pinned.prefix(TraySettings.maxPinnedPipelines))
        while slots.count <= slot { slots.append("") }
        if let id { for i in slots.indices where slots[i] == id { slots[i] = "" } }
        slots[slot] = id ?? ""
        return trimmed(slots)
    }

    /// `pinned` without `id` (a deleted user pipeline); its slot becomes free.
    static func removing(_ id: String, from pinned: [String]) -> [String] {
        trimmed(pinned.map { $0 == id ? "" : $0 })
    }

    private static func trimmed(_ slots: [String]) -> [String] {
        var slots = slots
        while slots.last?.isEmpty == true { slots.removeLast() }
        return slots
    }
}
