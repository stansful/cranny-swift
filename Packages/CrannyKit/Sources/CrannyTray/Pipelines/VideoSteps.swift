// CrannyTray/Pipelines/VideoSteps.swift — Compress video with AVAssetExportSession (HEVC 1080p, falling back to
// H.264 720p): `export(to:as:)` on macOS 15+, the older `export()` on 14 (ARCHITECTURE.md §7.8). Cancelling the
// pipeline task cancels the export.
import AVFoundation
import Foundation

nonisolated enum VideoSteps {
    /// Presets in order of preference.
    static let presets = [AVAssetExportPresetHEVC1920x1080, AVAssetExportPreset1280x720]

    /// A smaller MP4 named "<name> (compressed).mp4" in `directory`.
    static func compressVideo(_ input: URL, into directory: URL, naming: OutputNaming) async throws -> URL {
        let asset = AVURLAsset(url: input)
        guard (try? await asset.load(.isExportable)) == true else { throw TrayError.unsupportedFile(input.lastPathComponent) }
        var chosen: String?
        for preset in presets where await AVAssetExportSession.compatibility(ofExportPreset: preset, with: asset, outputFileType: .mp4) {
            chosen = preset
            break
        }
        guard let preset = chosen, let session = AVAssetExportSession(asset: asset, presetName: preset) else {
            throw TrayError.videoFailed
        }
        let base = input.deletingPathExtension().lastPathComponent
        let output = OutputNaming.uniqueURL(base: naming.compressed(base), ext: "mp4", in: directory)
        session.shouldOptimizeForNetworkUse = true
        do {
            if #available(macOS 15, *) {
                try await session.export(to: output, as: .mp4)
            } else {
                try await legacyExport(session, to: output)
            }
        } catch is CancellationError {
            try? FileManager.default.removeItem(at: output)
            throw CancellationError()
        } catch {
            try? FileManager.default.removeItem(at: output)
            if Task.isCancelled { throw CancellationError() }
            throw TrayError.videoFailed
        }
        if Task.isCancelled {
            try? FileManager.default.removeItem(at: output)
            throw CancellationError()
        }
        return output
    }

    /// macOS 14: `export()` does not observe task cancellation, so cancel the session from the handler.
    private static func legacyExport(_ session: AVAssetExportSession, to output: URL) async throws {
        session.outputURL = output
        session.outputFileType = .mp4
        let box = SessionBox(session)
        await withTaskCancellationHandler {
            await box.session.export()
        } onCancel: {
            box.session.cancelExport()
        }
        if Task.isCancelled { throw CancellationError() }
        guard session.status == .completed else { throw TrayError.videoFailed }
    }
}

/// `AVAssetExportSession.cancelExport()` is documented as callable from any thread; the box only carries the
/// reference into the cancellation handler.
private nonisolated final class SessionBox: @unchecked Sendable {
    let session: AVAssetExportSession
    init(_ session: AVAssetExportSession) { self.session = session }
}
