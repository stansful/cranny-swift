// CrannyTray/Store/TrayIndexFile.swift — the one writer of `index.json`, in the order the store made its changes.
//
// Every write carries the store's revision, and a write older than the newest one on disk is dropped. Without it a
// debounced save still in flight at quit could land after the synchronous terminate write and bring back an older
// list (under Clear on quit: the items whose copies were just deleted). Each write stages its bytes in a hidden file
// beside the index with no lock held; only the compare-and-rename that publishes it runs under the lock, so a
// background save delays the quit write by one rename(2), never by disk I/O (the timer's state file works the same).
// The JSON is compact (no pretty-printing or key sorting): it is internal, and every reader accepts either form.
import Darwin
import Foundation
import os

nonisolated final class TrayIndexFile: Sendable {
    let url: URL
    /// The revision of the newest index on disk. Held only while publishing, so publishes never interleave.
    private let newestWritten = OSAllocatedUnfairLock(initialState: 0)

    init(url: URL) { self.url = url }

    /// An index written under a hidden name beside `index.json`, not yet published.
    struct Staged: Sendable {
        let file: URL
        let revision: Int
    }

    /// Writes `index` as `revision` unless a newer revision is already on disk. Returns whether it wrote.
    @discardableResult func write(_ index: TrayIndex, revision: Int) throws -> Bool {
        guard let staged = try stage(index, revision: revision) else { return false }
        return try publish(staged)
    }

    /// `write` on the global executor (never on the main actor).
    @concurrent func writeInBackground(_ index: TrayIndex, revision: Int) async throws -> Bool {
        try write(index, revision: revision)
    }

    /// The first half of `write`: the encoded index in a hidden file beside `index.json`. nil (and no I/O) when a
    /// newer revision is already on disk.
    func stage(_ index: TrayIndex, revision: Int) throws -> Staged? {
        guard newestWritten.withLock({ revision > $0 }) else { return nil }
        let data = try JSONEncoder().encode(index)
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // Same folder as the index, so the rename that publishes it stays on one volume and is atomic.
        let file = directory.appending(path: ".\(url.lastPathComponent).\(UUID().uuidString).tmp", directoryHint: .notDirectory)
        try data.write(to: file)
        return Staged(file: file, revision: revision)
    }

    /// The second half: renames the staged file over `index.json`, unless a newer revision was published meanwhile
    /// (then the staged file is deleted). Returns whether it published.
    @discardableResult func publish(_ staged: Staged) throws -> Bool {
        var published = false
        defer { if !published { try? FileManager.default.removeItem(at: staged.file) } }
        let url = self.url
        published = try newestWritten.withLock { newest in
            guard staged.revision > newest else { return false }
            guard rename(staged.file.path, url.path) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
            newest = staged.revision
            return true
        }
        return published
    }
}
