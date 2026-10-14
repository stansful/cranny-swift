// CrannyTray/Pipelines/PipelineChipSet.swift — which actions the chip row offers for a selection (DESIGN.md §8.2):
// only actions valid for EVERY selected item. A pure function of the selected content types, so it is tested.
import Foundation
import UniformTypeIdentifiers

nonisolated struct PipelineChipSet: Equatable, Sendable {
    /// Images: Compress, Convert ▾, Resize ▾.
    var compress = false
    /// Writable formats other than the one every selected image already has.
    var convertFormats: [TrayImageFormat] = []
    var resizeOptions: [TrayResize] = []
    /// Zip archives.
    var unzip = false
    /// Anything: Zip, Copy paths, AirDrop.
    var zip = false
    var copyPaths = false
    var airDrop = false
    /// Built-ins behind the "…" chip (Remove background, Copy text, Make PDF, Compress video…).
    var more: [PipelineDefinition] = []
    /// User pipelines (✦) that take every selected item.
    var user: [PipelineDefinition] = []

    static func make(types: [UTType], userPipelines: [PipelineDefinition], maxDimension: Int,
                     writable: [TrayImageFormat] = ImageSteps.writableFormats) -> PipelineChipSet {
        var set = PipelineChipSet()
        guard !types.isEmpty else { return set }
        let images = types.allSatisfy { $0.conforms(to: .image) }
        let printable = types.allSatisfy { $0.conforms(to: .image) || $0.conforms(to: .pdf) }
        let movies = types.allSatisfy { $0.conforms(to: .movie) }
        let archives = types.allSatisfy { $0.conforms(to: .zip) }
        if images {
            set.compress = true
            let formats = Set(types.map { TrayImageFormat(type: $0) })
            let shared = formats.count == 1 ? formats.first ?? nil : nil
            set.convertFormats = writable.filter { $0 != shared }
            // 50 % · max <setting> · max 2048 (or 1600 when the setting is 2048), smaller sizes first.
            let other = maxDimension == 2048 ? 1600 : 2048
            let sizes: [TrayResize] = other < maxDimension
                ? [.maxDimension(pixels: other), .maxDimension(pixels: 0)]
                : [.maxDimension(pixels: 0), .maxDimension(pixels: other)]
            set.resizeOptions = [.scale(percent: 50)] + sizes
            set.more += [BuiltinPipelines.removeBackground, BuiltinPipelines.copyText, BuiltinPipelines.stripMetadata]
        }
        if printable { set.more.append(BuiltinPipelines.makePDF) }
        if movies { set.more.append(BuiltinPipelines.compressVideo) }
        set.unzip = archives
        set.zip = true
        set.copyPaths = true
        set.airDrop = true
        set.user = userPipelines.filter { $0.accepts(types) }
        return set
    }
}
