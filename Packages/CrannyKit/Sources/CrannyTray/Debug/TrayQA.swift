// CrannyTray/Debug/TrayQA.swift — Debug-only launch arguments for visual QA of the Tray (docs/CONTRIBUTING.md
// "Visual QA hooks"; combine with the shell's `--qa-state open --qa-page tray`):
//
//   --qa-tray-samples           use throw-away folders and keep generated sample files (never the user's Tray)
//   --qa-tray-select <n>        select the first n items (chip row)
//   --qa-tray-states            show a running pipeline, a failure, a fresh result and a file that could not be kept
//   --qa-tray-catch <uti,…>     the Tray page shows the drag catch view for these types (e.g. public.png)
//   --qa-tray-quicklook         open Quick Look on the first item after 2 s (Cranny's own non-activating preview panel)
//   --qa-tray-settings-bottom   Settings ▸ Tray opens scrolled to its last section
//
// Nothing here is compiled into Release builds; no input is synthesized.
import AppKit
import CoreGraphics
import CrannyCore
import Foundation
import ImageIO
import os
import UniformTypeIdentifiers

enum TrayQA {
    #if DEBUG
    private static let arguments = ProcessInfo.processInfo.arguments
    private static func value(_ name: String) -> String? {
        guard let i = arguments.firstIndex(of: name), i + 1 < arguments.count else { return nil }
        return arguments[i + 1]
    }
    static var usesSamples: Bool { arguments.contains("--qa-tray-samples") }
    /// Types for the catch view on the Tray page, if requested.
    static var catchTypes: [UTType]? {
        value("--qa-tray-catch").map { $0.split(separator: ",").compactMap { UTType(String($0)) } }
    }
    static var directories: TrayDirectories? { usesSamples ? .temporary() : nil }
    static var scrollsSettingsToBottom: Bool { arguments.contains("--qa-tray-settings-bottom") }
    #else
    static var scrollsSettingsToBottom: Bool { false }
    static var catchTypes: [UTType]? { nil }
    static var directories: TrayDirectories? { nil }
    #endif

    /// Keeps generated sample files and applies the requested states (Debug + `--qa-tray-samples` only).
    @MainActor static func seedIfRequested(_ store: TrayStore) async {
        #if DEBUG
        guard usesSamples else { return }
        let log = Log.logger(.tray)
        let folder = store.directories.work.deletingLastPathComponent().appending(path: "Samples", directoryHint: .isDirectory)
        let files = await TrayQASamples.write(into: folder)
        await store.keep(files, opensTray: false)
        log.info("QA: \(files.count, privacy: .public) sample file(s) in the Tray")
        if let n = value("--qa-tray-select").flatMap(Int.init) { store.selection.set(Array(store.order.prefix(n))) }
        if arguments.contains("--qa-tray-states"), store.items.count >= 4 {
            let ids = store.order
            store.jobs.append(TrayJob(id: UUID(), pipelineID: "builtin.compress", title: store.title(of: BuiltinPipelines.compress),
                                      sourceIDs: [ids[1]], placeholderName: nil, progress: 0.42))
            store.failures[ids[2]] = TrayError.notSmaller.errorDescription
            store.freshItems.insert(ids[3])
            let unkept = "Scan 2026-10-14.pdf"
            store.jobs.append(TrayJob(id: UUID(), pipelineID: TrayStore.keepJobID, title: unkept, sourceIDs: [],
                                      placeholderName: unkept, failure: TrayError.cannotRead(unkept).errorDescription))
        }
        if arguments.contains("--qa-tray-quicklook") {
            try? await Task.sleep(for: .seconds(2))
            store.toggleQuickLook(store.order.first)
        }
        #endif
    }
}

#if DEBUG
/// Sample files drawn with CoreGraphics (no assets): photos, a screenshot-like PNG, a PDF, a zip and a note.
nonisolated enum TrayQASamples {
    @concurrent static func write(into folder: URL) async -> [URL] {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var urls: [URL] = []
        let images: [(String, UTType, [CGColor])] = [
            ("IMG_2041.jpg", .jpeg, [CGColor(srgbRed: 0.98, green: 0.55, blue: 0.27, alpha: 1), CGColor(srgbRed: 0.55, green: 0.24, blue: 0.60, alpha: 1)]),
            ("notch.heic", .heic, [CGColor(srgbRed: 0.18, green: 0.83, blue: 0.78, alpha: 1), CGColor(srgbRed: 0.04, green: 0.04, blue: 0.08, alpha: 1)]),
            ("hero@2x.png", .png, [CGColor(srgbRed: 0.33, green: 0.78, blue: 0.95, alpha: 1), CGColor(srgbRed: 0.55, green: 0.42, blue: 1.0, alpha: 1)]),
        ]
        for (name, type, colors) in images {
            let url = folder.appending(path: name)
            if writeGradient(to: url, type: type, colors: colors) { urls.append(url) }
        }
        let pdf = folder.appending(path: "Brief.pdf")
        if writePDF(to: pdf) { urls.insert(pdf, at: 0) }
        let note = folder.appending(path: "Release notes.txt")
        if (try? "Cranny 0.1 — Tray, AirDrop and pipelines.\n".write(to: note, atomically: true, encoding: .utf8)) != nil { urls.append(note) }
        let zipSource = folder.appending(path: "assets", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: zipSource, withIntermediateDirectories: true)
        if let first = urls.first(where: { $0.pathExtension == "png" }) {
            try? FileManager.default.copyItem(at: first, to: zipSource.appending(path: first.lastPathComponent))
        }
        if let zip = try? await ArchiveSteps.zip([zipSource], baseName: "assets", into: folder, scratch: folder) { urls.append(zip) }
        return urls
    }

    private static func writeGradient(to url: URL, type: UTType, colors: [CGColor]) -> Bool {
        let width = 1200, height = 800
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let gradient = CGGradient(colorsSpace: space, colors: colors as CFArray, locations: [0, 1]) else { return false }
        context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: width, y: height), options: [])
        context.setFillColor(CGColor(gray: 1, alpha: 0.18))
        context.fillEllipse(in: CGRect(x: width / 3, y: height / 4, width: width / 3, height: width / 3))
        guard let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil) else { return false }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination)
    }

    private static func writePDF(to url: URL) -> Bool {
        var box = CGRect(x: 0, y: 0, width: 595, height: 842)
        guard let context = CGContext(url as CFURL, mediaBox: &box, nil) else { return false }
        context.beginPDFPage(nil)
        context.setFillColor(CGColor(gray: 0.96, alpha: 1))
        context.fill(box)
        context.setFillColor(CGColor(gray: 0.2, alpha: 1))
        for row in 0..<12 { context.fill(CGRect(x: 60, y: 720 - row * 44, width: row % 3 == 0 ? 300 : 470, height: 14)) }
        context.endPDFPage()
        context.closePDF()
        return true
    }
}
#endif
