// CrannyTray/Pipelines/PDFSteps.swift — Make PDF: images become pages, PDFs are appended page by page (PDFKit,
// ARCHITECTURE.md §7.8). Runs in the pipeline's background context; the document never leaves this function.
import AppKit
import Foundation
import PDFKit
import UniformTypeIdentifiers

nonisolated enum PDFSteps {
    /// One PDF named after the first input, in `directory`.
    static func makePDF(_ inputs: [URL], into directory: URL) throws -> URL {
        guard let first = inputs.first else { throw TrayError.pdfFailed }
        let document = PDFDocument()
        for input in inputs {
            try Task.checkCancellation()
            let type = TrayItem.contentType(of: input)
            if type.conforms(to: .pdf) {
                guard let pdf = PDFDocument(url: input) else { throw TrayError.cannotRead(input.lastPathComponent) }
                for index in 0..<pdf.pageCount {
                    if let page = pdf.page(at: index) { document.insert(page, at: document.pageCount) }
                }
            } else if type.conforms(to: .image) {
                // NSImage applies the EXIF orientation, so portrait photos stay portrait.
                guard let image = NSImage(contentsOf: input), let page = PDFPage(image: image) else {
                    throw TrayError.cannotRead(input.lastPathComponent)
                }
                document.insert(page, at: document.pageCount)
            } else {
                throw TrayError.unsupportedFile(input.lastPathComponent)
            }
        }
        guard document.pageCount > 0 else { throw TrayError.pdfFailed }
        let output = OutputNaming.uniqueURL(base: first.deletingPathExtension().lastPathComponent, ext: "pdf", in: directory)
        guard document.write(to: output) else {
            try? FileManager.default.removeItem(at: output)
            throw TrayError.pdfFailed
        }
        return output
    }
}
