// CrannyTimer/Model/TimerStateFile.swift — `AppPaths/timer/state.json` (ARCHITECTURE.md §3.11: timer state is content,
// not settings, so "Reset All Settings" keeps a running timer).
//
// Writes happen off the main actor (`@concurrent`) in the order the model made them: each write carries a sequence
// number and a write older than the newest one on disk is dropped. The terminate hook writes synchronously (it must
// finish before the process exits); the same lock orders it against a background write still in flight.
import CrannyCore
import Foundation
import os

nonisolated private let log = Log.logger(.timer)

/// What is persisted. `version` lets a future format migrate instead of discarding the file.
nonisolated struct TimerSnapshot: Codable, Equatable, Sendable {
    static let currentVersion = 1
    var version = Self.currentVersion
    var state: TimerState
    /// Seconds of the most recent start (the "Start timer" shortcut and the set-up ring reuse it).
    var lastDuration: Int

    init(state: TimerState, lastDuration: Int) {
        self.state = state
        self.lastDuration = lastDuration
    }
}

nonisolated final class TimerStateFile: Sendable {
    let url: URL
    /// The sequence number of the newest snapshot on disk. Held while writing, so writes never interleave.
    private let newestWritten = OSAllocatedUnfairLock(initialState: 0)

    init(url: URL) { self.url = url }

    /// `<directory>/state.json`.
    convenience init(directory: URL) {
        self.init(url: directory.appending(path: "state.json", directoryHint: .notDirectory))
    }

    /// The saved snapshot, or nil if there is none. A file that cannot be decoded is moved aside
    /// (`state.json.corrupt-<time>`) and logged, so a bad write never blocks the timer.
    func load() -> TimerSnapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        do {
            let snapshot = try JSONDecoder().decode(TimerSnapshot.self, from: data)
            guard snapshot.version <= TimerSnapshot.currentVersion else {
                log.error("state.json has newer version \(snapshot.version, privacy: .public); ignoring it")
                return nil
            }
            return snapshot
        } catch {
            let aside = url.appendingPathExtension("corrupt-\(Int(Date().timeIntervalSince1970))")
            try? FileManager.default.moveItem(at: url, to: aside)
            log.error("corrupt state.json moved aside: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Writes `snapshot` atomically unless a newer sequence number is already on disk. Returns whether it wrote.
    @discardableResult func write(_ snapshot: TimerSnapshot, sequence: Int) throws -> Bool {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(snapshot)
        let url = self.url
        return try newestWritten.withLock { newest in
            guard sequence > newest else { return false }
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            newest = sequence
            return true
        }
    }

    /// `write` on the global executor (never on the main actor). Failures are logged: the timer keeps working.
    @concurrent func writeInBackground(_ snapshot: TimerSnapshot, sequence: Int) async {
        do { try write(snapshot, sequence: sequence) } catch {
            log.error("could not save state.json: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// `load` on the global executor.
    @concurrent func loadInBackground() async -> TimerSnapshot? { load() }
}
