// CrannyAppShell/Overlay/FilePromiseResolver.swift — turns dropped file promises (Photos, Mail attachments,
// Safari images) into files before any drop zone sees them (ARCHITECTURE.md §5.6, R1 §5.1 [UNVERIFIED there]).
// Files land in `<caches>/tray/Incoming/<uuid>/`; the drop handler awaits the URLs. A source that never delivers
// is given up after a minute. Every taker copies or stages what it keeps inside its awaited drop call, so the drop
// router deletes the folder once the drop is delivered (`discard`), and the whole `Incoming` folder is swept at
// launch and at quit (a crash or a quit mid-drop): promised copies of private photos and attachments never pile up.
//
// Threading: AppKit calls each promise's reader block on `queue`, a background operation queue. The SDK does not
// mark that block Sendable, so a closure written inside a main-actor type would be inferred main-actor isolated
// and Swift 6 would trap on its executor check the moment AppKit calls it. That is why this type is `nonisolated`
// and the reader is built by `makeReader(for:)`: a `@Sendable` closure with no actor, which only touches the
// lock-protected `PromiseCollector`.
import AppKit
import CrannyCore
import Foundation
import os

nonisolated enum FilePromiseResolver {
    /// How long to wait for a promise before dropping it (a crashed source never calls back).
    static let timeout: Duration = .seconds(60)

    /// Where AppKit runs the readers (and the sources write the files): never the main thread.
    private static let queue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "app.cranny.Cranny.filePromises"
        queue.qualityOfService = .userInitiated
        return queue
    }()

    /// `<caches>/tray/Incoming/`: every drop's folder is inside it.
    static func incomingRoot(paths: AppPaths) -> URL {
        paths.caches.appending(path: ModuleID.tray.rawValue, directoryHint: .isDirectory)
            .appending(path: "Incoming", directoryHint: .isDirectory)
    }

    /// `incomingDirectory(paths:)` off the main actor (the drop router creates one per promise drop, §9.2).
    @concurrent static func makeIncomingDirectory(paths: AppPaths) async -> URL? {
        incomingDirectory(paths: paths)
    }

    /// A fresh `Incoming/<uuid>/` directory in the tray's cache, or nil if it cannot be created.
    static func incomingDirectory(paths: AppPaths) -> URL? {
        do {
            let url = incomingRoot(paths: paths).appending(path: UUID().uuidString, directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        } catch {
            let code = (error as NSError).code, domain = (error as NSError).domain
            Log.logger(.overlay).error("file promises: no incoming directory: \(domain, privacy: .public) \(code, privacy: .public) \(error.localizedDescription, privacy: .private)")
            return nil
        }
    }

    /// Deletes one drop's folder after delivery (off the main actor: a promised video can be large).
    @concurrent static func discard(_ directory: URL) async {
        remove(directory)
    }

    /// Deletes every drop folder left behind: at launch (off the main actor) …
    @concurrent static func sweepIncoming(paths: AppPaths) async {
        sweepIncomingNow(paths: paths)
    }

    /// … and at quit, synchronously (`applicationWillTerminate`).
    static func sweepIncomingNow(paths: AppPaths) {
        remove(incomingRoot(paths: paths))
    }

    private static func remove(_ url: URL) {
        do { try FileManager.default.removeItem(at: url) } catch CocoaError.fileNoSuchFile {
            // Nothing to delete.
        } catch {
            let code = (error as NSError).code, domain = (error as NSError).domain
            Log.logger(.overlay).error("file promises: could not delete a drop folder: \(domain, privacy: .public) \(code, privacy: .public)")
        }
    }

    /// Receives every promise into `directory`; returns the files that arrived (in no particular order).
    static func resolve(_ receivers: [NSFilePromiseReceiver], into directory: URL,
                        timeout: Duration = Self.timeout) async -> [URL] {
        var urls: [URL] = []
        for receiver in receivers { urls += await receive(receiver, into: directory, timeout: timeout) }
        return urls
    }

    private static func receive(_ receiver: NSFilePromiseReceiver, into directory: URL, timeout: Duration) async -> [URL] {
        let collector = PromiseCollector(expected: max(receiver.fileTypes.count, 1))
        return await withCheckedContinuation { (continuation: CheckedContinuation<[URL], Never>) in
            collector.onFinish = { continuation.resume(returning: $0) }
            receiver.receivePromisedFiles(atDestination: directory, options: [:], operationQueue: queue,
                                          reader: makeReader(for: collector))
            collector.armTimeout(timeout)
        }
    }

    /// The block AppKit calls once per promised file, on `queue`. Nonisolated and `@Sendable` (see the header).
    static func makeReader(for collector: PromiseCollector) -> @Sendable (URL, (any Error)?) -> Void {
        { url, error in
            if let error {
                let code = (error as NSError).code, domain = (error as NSError).domain
                Log.logger(.overlay).error("file promise failed: \(domain, privacy: .public) \(code, privacy: .public) \(error.localizedDescription, privacy: .private)")
                collector.add(nil)
            } else {
                collector.add(url)
            }
        }
    }
}

/// Counts promise callbacks (on the operation queue) and finishes exactly once: when every promised file has
/// called back, or when the timeout gives up. Thread-safe through the lock; `onFinish` is set before any callback
/// can run and never changes afterwards. Finishing cancels the timeout, so no sleep outlives the drop.
nonisolated final class PromiseCollector: @unchecked Sendable {
    private struct State {
        var urls: [URL] = []
        var remaining: Int
        var done = false
        var timeout: Task<Void, Never>?
    }
    private let state: OSAllocatedUnfairLock<State>
    var onFinish: @Sendable ([URL]) -> Void = { _ in }

    init(expected: Int) { state = OSAllocatedUnfairLock(initialState: State(remaining: expected)) }

    /// Gives up after `duration` unless every file arrived first.
    func armTimeout(_ duration: Duration) {
        let task = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            self?.giveUp()
        }
        let finished = state.withLock { s in
            if !s.done { s.timeout = task }
            return s.done
        }
        if finished { task.cancel() }
    }

    func add(_ url: URL?) {
        let finished: (urls: [URL], timeout: Task<Void, Never>?)? = state.withLock { s in
            if let url { s.urls.append(url) }
            s.remaining -= 1
            guard s.remaining <= 0, !s.done else { return nil }
            s.done = true
            defer { s.timeout = nil }
            return (s.urls, s.timeout)
        }
        guard let finished else { return }
        finished.timeout?.cancel()
        onFinish(finished.urls)
    }

    func giveUp() {
        let finished: [URL]? = state.withLock { s in
            guard !s.done else { return nil }
            s.done = true
            s.timeout = nil
            return s.urls
        }
        guard let finished else { return }
        Log.logger(.overlay).info("file promise timed out with \(finished.count, privacy: .public) file(s)")
        onFinish(finished)
    }

    /// True while the timeout task is still pending (tests).
    var hasPendingTimeout: Bool { state.withLock { $0.timeout != nil } }
}
