// CrannyTray/Pipelines/ArchiveSteps.swift — Zip and Unzip with /usr/bin/ditto (Finder-compatible archives, R3 §8),
// run through Core's `ProcessRunner` (both pipes drained; cancelling the task terminates ditto).
import CrannyCore
import Foundation

nonisolated enum ArchiveSteps {
    static let ditto = "/usr/bin/ditto"

    /// One archive of `inputs` named `<baseName>.zip` in `directory`. Several items are staged (APFS clones) into a
    /// folder named like the archive, so unzipping gives one tidy folder (R3 §8).
    static func zip(_ inputs: [URL], baseName: String, into directory: URL, scratch: URL) async throws -> URL {
        guard let first = inputs.first else { throw TrayError.archiveFailed }
        let output = OutputNaming.uniqueURL(base: baseName, ext: "zip", in: directory)
        var source = first
        var staging: URL?
        if inputs.count > 1 {
            let stage = scratch.appending(path: "stage-\(UUID().uuidString)", directoryHint: .isDirectory)
            let folder = stage.appending(path: baseName, directoryHint: .isDirectory)
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                var taken = Set<String>()
                for input in inputs {
                    try Task.checkCancellation()
                    let name = OutputNaming.unique(base: input.deletingPathExtension().lastPathComponent,
                                                   ext: input.pathExtension, taken: taken)
                    taken.insert(name)
                    try FileManager.default.copyItem(at: input, to: folder.appending(path: name))
                }
            } catch is CancellationError {
                try? FileManager.default.removeItem(at: stage)
                throw CancellationError()
            } catch {
                try? FileManager.default.removeItem(at: stage)
                throw TrayError.archiveFailed
            }
            source = folder
            staging = stage
        }
        defer { if let staging { try? FileManager.default.removeItem(at: staging) } }
        // --keepParent keeps a folder's name as the archive's root; for a single file it would wrap the file in its
        // parent folder, so it is used for folders only.
        let isFolder = (try? source.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        try await runDitto(["-c", "-k", "--sequesterRsrc"] + (isFolder ? ["--keepParent"] : []) + [source.path, output.path],
                           cleaningUp: output, failure: .archiveFailed)
        return output
    }

    /// Extracts `archive` into `directory`: the single top-level item, or a folder named after the archive.
    static func unzip(_ archive: URL, into directory: URL, scratch: URL) async throws -> URL {
        let target = scratch.appending(path: "unzip-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: target) }
        do { try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true) } catch {
            throw TrayError.cannotWrite
        }
        try await runDitto(["-x", "-k", archive.path, target.path], cleaningUp: nil, failure: .unarchiveFailed)
        let entries = ((try? FileManager.default.contentsOfDirectory(at: target, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.lastPathComponent != "__MACOSX" && $0.lastPathComponent != ".DS_Store" }
        let base = archive.deletingPathExtension().lastPathComponent
        do {
            if entries.count == 1, let only = entries.first {
                let output = OutputNaming.uniqueURL(base: only.deletingPathExtension().lastPathComponent,
                                                    ext: only.pathExtension, in: directory)
                try FileManager.default.moveItem(at: only, to: output)
                return output
            }
            let output = OutputNaming.uniqueURL(base: base, ext: "", in: directory)
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            for entry in entries {
                try FileManager.default.moveItem(at: entry, to: output.appending(path: entry.lastPathComponent))
            }
            return output
        } catch {
            throw TrayError.unarchiveFailed
        }
    }

    private static func runDitto(_ arguments: [String], cleaningUp partial: URL?, failure: TrayError) async throws {
        let result: ProcessOutput
        do {
            result = try await ProcessRunner.run(ditto, arguments, qualityOfService: .utility)   // a pipeline nobody waits on
        } catch {
            throw failure
        }
        if Task.isCancelled {
            if let partial { try? FileManager.default.removeItem(at: partial) }
            throw CancellationError()
        }
        guard result.succeeded else {
            if let partial { try? FileManager.default.removeItem(at: partial) }
            throw failure
        }
    }
}
