// CrannyTray/TrayError.swift — everything that can go wrong in the Tray, as one localized line each
// (ARCHITECTURE.md §9.3; DESIGN.md §8.2 "Error": the tile's tooltip and accessibility value say what failed).
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

    var errorDescription: String? {
        switch self {
        case .cannotRead(let name):
            String(localized: "Couldn’t read “\(name)”", bundle: .module, comment: "Tray error (tile tooltip): a file could not be read")
        case .cannotWrite:
            String(localized: "Couldn’t save the result", bundle: .module, comment: "Tray error (tile tooltip): the result file could not be written")
        case .unsupportedFile(let name):
            String(localized: "This doesn’t work with “\(name)”", bundle: .module, comment: "Tray error (tile tooltip): the action does not apply to this kind of file")
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
        }
    }
}
