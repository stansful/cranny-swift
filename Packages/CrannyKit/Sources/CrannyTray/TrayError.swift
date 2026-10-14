// CrannyTray/TrayError.swift — everything that can go wrong in the Tray, as one localized line each
// (ARCHITECTURE.md §9.3; DESIGN.md §8.2 "Error": the tile's tooltip and accessibility value say what failed).
import CrannyCore
import Foundation

nonisolated enum TrayError: Error, LocalizedError, Equatable, Sendable {
    /// The file could not be read (gone, unreadable, not a format the step understands).
    case cannotRead(String)
    /// The result could not be written.
    case cannotWrite
    /// The step needs another kind of file ("Compress" on a PDF).
    case unsupportedFile(String)
    /// This Mac cannot write the format (queried at runtime).
    case formatUnavailable(String)
    /// Compressing would not make the file smaller.
    case notSmaller
    case archiveFailed
    case unarchiveFailed
    /// Remove background found no subject.
    case noSubject
    /// Copy text found no text.
    case noText
    case pdfFailed
    case videoFailed
    /// A linked file was moved away or deleted.
    case fileMissing
    /// A dropped file could not be kept (not enough space, the Tray folder is not writable).
    case cannotKeep(String)

    var errorDescription: String? {
        switch self {
        case .cannotRead(let name):
            String(localized: "Couldn’t read “\(name.crannyIsolated)”", bundle: .module, comment: "Tray error (tile tooltip): a file could not be read")
        case .cannotWrite:
            String(localized: "Couldn’t save the result", bundle: .module, comment: "Tray error (tile tooltip): the result file could not be written")
        case .unsupportedFile(let name):
            String(localized: "This doesn’t work with “\(name.crannyIsolated)”", bundle: .module, comment: "Tray error (tile tooltip): the action does not apply to this kind of file")
        case .formatUnavailable(let format):
            String(localized: "This Mac can’t write \(format) files", bundle: .module, comment: "Tray error (tile tooltip): image format not supported for writing; the argument is a format name such as AVIF")
        case .notSmaller:
            String(localized: "Already as small as it gets", bundle: .module, comment: "Tray error (tile tooltip): compressing would not make the file smaller")
        case .archiveFailed:
            String(localized: "Couldn’t create the archive", bundle: .module, comment: "Tray error (tile tooltip): zip failed")
        case .unarchiveFailed:
            String(localized: "Couldn’t open the archive", bundle: .module, comment: "Tray error (tile tooltip): unzip failed")
        case .noSubject:
            String(localized: "No subject found", bundle: .module, comment: "Tray error (tile tooltip): Remove background found nothing in front")
        case .noText:
            String(localized: "No text found", bundle: .module, comment: "Tray error (tile tooltip): Copy text recognized nothing")
        case .pdfFailed:
            String(localized: "Couldn’t make the PDF", bundle: .module, comment: "Tray error (tile tooltip): Make PDF failed")
        case .videoFailed:
            String(localized: "Couldn’t compress the video", bundle: .module, comment: "Tray error (tile tooltip): video export failed")
        case .fileMissing:
            String(localized: "The file is no longer there", bundle: .module, comment: "Tray error (tile tooltip): a linked file was moved or deleted")
        case .cannotKeep(let name):
            String(localized: "Couldn’t keep “\(name.crannyIsolated)”", bundle: .module, comment: "Tray error (tile tooltip): a dropped file could not be copied into the Tray, for example because the disk is full")
        }
    }

    /// The case name without its payload: safe to log publicly (no file names, ARCHITECTURE.md §9.3).
    var caseName: String {
        switch self {
        case .cannotRead: "cannotRead"
        case .cannotWrite: "cannotWrite"
        case .unsupportedFile: "unsupportedFile"
        case .formatUnavailable: "formatUnavailable"
        case .notSmaller: "notSmaller"
        case .archiveFailed: "archiveFailed"
        case .unarchiveFailed: "unarchiveFailed"
        case .noSubject: "noSubject"
        case .noText: "noText"
        case .pdfFailed: "pdfFailed"
        case .videoFailed: "videoFailed"
        case .fileMissing: "fileMissing"
        case .cannotKeep: "cannotKeep"
        }
    }

    /// Why keeping `name` failed, from the copy's error: reading the original, or writing into the Tray.
    static func keeping(_ name: String, failedWith error: any Error) -> TrayError {
        let ns = error as NSError
        let readErrors = CocoaError.Code.fileReadUnknown.rawValue..<CocoaError.Code.fileWriteUnknown.rawValue   // 256..<512
        return ns.domain == NSCocoaErrorDomain && readErrors.contains(ns.code) ? .cannotRead(name) : .cannotKeep(name)
    }
}

/// What may be logged publicly about an error: its domain and code, or the Tray error's case. Descriptions name the
/// user's files, so they are only ever logged with `privacy: .private` (ARCHITECTURE.md §9.3).
nonisolated enum TrayLogCode {
    static func of(_ error: any Error) -> String {
        if let tray = error as? TrayError { return "TrayError.\(tray.caseName)" }
        let ns = error as NSError
        return "\(ns.domain) \(ns.code)"
    }
}
