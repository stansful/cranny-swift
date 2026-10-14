// CrannyAppShell/Overlay/FilePromiseResolver.swift — turns dropped file promises (Photos, Mail attachments,
// Safari images) into files before any drop zone sees them (ARCHITECTURE.md §5.6, R1 §5.1 [UNVERIFIED there]).
// Files land in `<caches>/tray/Incoming/<uuid>/`; the promise readers run on a background operation queue and
// the drop handler awaits the URLs. A source that never delivers is given up after a minute.
import AppKit
import CrannyCore
import Foundation
import os

private let log = Log.logger(.overlay)

@MainActor enum FilePromiseResolver {
    /// How long to wait for a promise before dropping it (a crashed source never calls back).
    static let timeout: Duration = .seconds(60)

    private static let queue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "app.cranny.Cranny.filePromises"
        queue.qualityOfService = .userInitiated
        return queue
    }()

    /// A fresh `Incoming/<uuid>/` directory in the tray's cache, or nil if it cannot be created.
    static func incomingDirectory(paths: AppPaths) -> URL? {
        do {
            let url = try paths.cacheDirectory(for: .tray)
                .appending(path: "Incoming", directoryHint: .isDirectory)
                .appending(path: UUID().uuidString, directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        } catch {
            log.error("file promises: no incoming directory: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Receives every promise into `directory`; returns the files that arrived (in no particular order).
    static func resolve(_ receivers: [NSFilePromiseReceiver], into directory: URL) async -> [URL] {
        var urls: [URL] = []
        for receiver in receivers { urls += await receive(receiver, into: directory) }
        return urls
    }

    private static func receive(_ receiver: NSFilePromiseReceiver, into directory: URL) async -> [URL] {
        let expected = max(receiver.fileTypes.count, 1)
        let collector = PromiseCollector(expected: expected)
        return await withCheckedContinuation { (continuation: CheckedContinuation<[URL], Never>) in
            collector.onFinish = { continuation.resume(returning: $0) }
            receiver.receivePromisedFiles(atDestination: directory, options: [:], operationQueue: queue) { url, error in
                if let error {                                                   // on the operation queue
                    Log.logger(.overlay).error("file promise failed: \(error.localizedDescription, privacy: .public)")
                    collector.add(nil)
                } else {
                    collector.add(url)
                }
            }
            Task {
                try? await Task.sleep(for: timeout)
                collector.giveUp()
            }
        }
    }
}

/// Counts promise callbacks (on the operation queue) and finishes exactly once. Thread-safe through the lock;
/// `onFinish` is set before any callback can run and never changes afterwards.
private nonisolated final class PromiseCollector: @unchecked Sendable {
    private struct State { var urls: [URL] = []; var remaining: Int; var done = false }
    private let state: OSAllocatedUnfairLock<State>
    var onFinish: @Sendable ([URL]) -> Void = { _ in }

    init(expected: Int) { state = OSAllocatedUnfairLock(initialState: State(remaining: expected)) }

    func add(_ url: URL?) {
        let finished: [URL]? = state.withLock { s in
            if let url { s.urls.append(url) }
            s.remaining -= 1
            guard s.remaining <= 0, !s.done else { return nil }
            s.done = true
            return s.urls
        }
        if let finished { onFinish(finished) }
    }

    func giveUp() {
        let finished: [URL]? = state.withLock { s in
            guard !s.done else { return nil }
            s.done = true
            return s.urls
        }
        if let finished {
            Log.logger(.overlay).info("file promise timed out with \(finished.count, privacy: .public) file(s)")
            onFinish(finished)
        }
    }
}
