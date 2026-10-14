// CrannyTray/Pipelines/Pipeline.swift — what a pipeline is (DESIGN.md §8.2, ARCHITECTURE.md §7.8): a named chain
// of steps. Built-in actions and user pipelines (Settings ▸ Tray) are the same type; user pipelines are persisted in
// `TraySettings.userPipelines`, so every type here is a stable, `Codable` value. Never rename a case.
import Foundation
import UniformTypeIdentifiers

/// A chain of steps applied to the selected tray items or to files dropped on a pipeline zone.
public nonisolated struct PipelineDefinition: Codable, Hashable, Sendable, Identifiable {
    /// "builtin.compress", "builtin.zip"… or "user.<uuid>" (referenced by `TraySettings.pinnedPipelines`).
    public var id: String
    /// The user's name for a user pipeline; nil for built-ins, which are localized at use (`BuiltinPipelines`).
    public var name: String?
    /// SF Symbol of the chip and the drop zone.
    public var symbol: String
    public var steps: [PipelineStep]

    public init(id: String, name: String?, symbol: String, steps: [PipelineStep]) {
        self.id = id; self.name = name; self.symbol = symbol; self.steps = steps
    }

    /// A new, empty user pipeline.
    public static func newUserPipeline(name: String) -> PipelineDefinition {
        PipelineDefinition(id: "user.\(UUID().uuidString.lowercased())", name: name, symbol: "wand.and.stars", steps: [])
    }

    /// User pipelines carry the ✦ glyph and live in Settings; built-ins are always available.
    public var isUserPipeline: Bool { id.hasPrefix("user.") }
    /// What the first step needs; `.any` for an empty chain.
    var input: PipelineContent { steps.first?.input ?? .any }
    /// The content types a drop must conform to (catch zones and contextual chips).
    var acceptedTypes: [UTType] { input.types }

    /// True when every type in `types` is something the first step can take (DESIGN.md §8.2: chips are shown only
    /// when valid for every selected item). An empty or invalid chain accepts nothing.
    func accepts(_ types: [UTType]) -> Bool {
        guard !steps.isEmpty, PipelineValidation.problems(in: steps).isEmpty, !types.isEmpty else { return false }
        return types.allSatisfy { input.accepts($0) }
    }
}

/// One step of a pipeline. Steps that write files name their output after their input (`OutputNaming`).
public nonisolated enum PipelineStep: Codable, Hashable, Sendable {
    /// HEIC or JPEG at `TraySettings.jpegQuality`, same dimensions (DESIGN.md §8.2).
    case compress
    case convert(format: TrayImageFormat)
    case resize(to: TrayResize)
    /// Re-encodes without EXIF, GPS and other metadata.
    case stripMetadata
    /// Vision foreground mask → transparent PNG (macOS 14).
    case removeBackground
    /// Images and PDFs → one PDF.
    case makePDF
    /// HEVC 1080p export.
    case compressVideo
    case zip
    case unzip
    /// Copies the POSIX paths of the current files and confirms with a flash.
    case copyPaths
    /// Recognizes text in images (Vision) and copies it.
    case copyText
    /// Shows the current files in Finder.
    case reveal

    /// Every step, in the order the pipeline editor lists them.
    static let catalog: [PipelineStep] = [
        .compress, .convert(format: .jpeg), .resize(to: .maxDimension(pixels: 0)), .stripMetadata, .removeBackground,
        .makePDF, .compressVideo, .zip, .unzip, .copyPaths, .copyText, .reveal,
    ]

    /// What the step needs from the previous step (or from the dropped files).
    var input: PipelineContent {
        switch self {
        case .compress, .convert, .resize, .stripMetadata, .removeBackground, .copyText: .images
        case .makePDF: .printable
        case .compressVideo: .movies
        case .unzip: .archives
        case .zip, .copyPaths, .reveal: .any
        }
    }

    /// What the step hands to the next one; nil = the same files it received.
    var output: PipelineContent? {
        switch self {
        case .compress, .convert, .resize, .stripMetadata, .removeBackground: .images
        case .makePDF: .pdf
        case .compressVideo: .movies
        case .zip: .archives
        case .unzip: .any
        case .copyPaths, .copyText, .reveal: nil
        }
    }

    /// Steps that write files (results get an Undo chip and land in the Tray).
    var writesFiles: Bool { output != nil }

    /// The same kind of step, ignoring its parameters (the editor's step menu, `catalog` lookups).
    var kind: String {
        switch self {
        case .compress: "compress"
        case .convert: "convert"
        case .resize: "resize"
        case .stripMetadata: "stripMetadata"
        case .removeBackground: "removeBackground"
        case .makePDF: "makePDF"
        case .compressVideo: "compressVideo"
        case .zip: "zip"
        case .unzip: "unzip"
        case .copyPaths: "copyPaths"
        case .copyText: "copyText"
        case .reveal: "reveal"
        }
    }
}

/// Image formats ImageIO can write. Which ones are actually offered is decided at runtime from
/// `CGImageDestinationCopyTypeIdentifiers()` (AVIF encodes on macOS 27, WebP and JPEG XL do not; R3 §8).
public nonisolated enum TrayImageFormat: String, Codable, CaseIterable, Sendable {
    case jpeg, png, heic, tiff, avif

    var type: UTType {
        switch self {
        case .jpeg: .jpeg
        case .png: .png
        case .heic: .heic
        case .tiff: .tiff
        case .avif: UTType("public.avif") ?? .image
        }
    }
    var fileExtension: String {
        switch self {
        case .jpeg: "jpg"
        case .png: "png"
        case .heic: "heic"
        case .tiff: "tiff"
        case .avif: "avif"
        }
    }
    /// Shown in menus and chips; format names are not translated.
    var displayName: String {
        switch self {
        case .jpeg: "JPEG"
        case .png: "PNG"
        case .heic: "HEIC"
        case .tiff: "TIFF"
        case .avif: "AVIF"
        }
    }
    var isLossy: Bool { self == .jpeg || self == .heic || self == .avif }
    var supportsAlpha: Bool { self != .jpeg }
    /// The format whose UTType matches `type`, if it is one of ours.
    init?(type: UTType) {
        guard let match = Self.allCases.first(where: { type.conforms(to: $0.type) }) else { return nil }
        self = match
    }
}

/// Resize targets (DESIGN.md §8.2: 50 % · max 1600 · max 2048).
public nonisolated enum TrayResize: Codable, Hashable, Sendable {
    /// Percent of the original size (1…100).
    case scale(percent: Int)
    /// Longer side in pixels; 0 = `TraySettings.maxDimension`. Never enlarges.
    case maxDimension(pixels: Int)
}

/// The kind of content a step takes or makes (validation and contextual chips).
nonisolated enum PipelineContent: Equatable, Sendable {
    case images, movies, archives, pdf, printable, any

    var types: [UTType] {
        switch self {
        case .images: [.image]
        case .movies: [.movie]
        case .archives: [.zip]
        case .pdf: [.pdf]
        case .printable: [.image, .pdf]
        case .any: [.item]
        }
    }
    func accepts(_ type: UTType) -> Bool { types.contains { type.conforms(to: $0) } }

    /// Whether whatever `produced` makes is guaranteed to be something `self` takes.
    func isSatisfied(by produced: PipelineContent) -> Bool {
        switch (self, produced) {
        case (.any, _): true
        case (.printable, .images), (.printable, .pdf), (.printable, .printable): true
        default: self == produced
        }
    }
}

/// Why a chain cannot run as built (shown under the step in the pipeline editor).
nonisolated struct PipelineProblem: Equatable, Sendable {
    /// Index of the step that has nothing to work on.
    var stepIndex: Int
    var needs: PipelineContent
    var gets: PipelineContent
}

nonisolated enum PipelineValidation {
    /// Steps whose input is not guaranteed by the step before them. Empty = valid.
    static func problems(in steps: [PipelineStep]) -> [PipelineProblem] {
        var produced: PipelineContent?
        var problems: [PipelineProblem] = []
        for (index, step) in steps.enumerated() {
            if let produced, !step.input.isSatisfied(by: produced) {
                problems.append(PipelineProblem(stepIndex: index, needs: step.input, gets: produced))
            }
            if let out = step.output { produced = out } else if produced == nil { produced = step.input }
        }
        return problems
    }
}
