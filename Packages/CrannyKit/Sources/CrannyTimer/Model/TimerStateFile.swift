// CrannyTimer/Model/TimerStateFile.swift — `AppPaths/timer/state.json` (ARCHITECTURE.md §3.11: timer state is content,
// not settings, so "Reset All Settings" keeps a running timer).
//
// Built on Core's `JSONDocumentFile`: writes happen off the main actor (`@concurrent`) in the order the model made them
// (each carries a sequence number; a write older than the newest one on disk is dropped), the terminate hook writes
// synchronously, and only the compare-and-rename that publishes a staged file runs under the lock, so a background
// write in flight delays the quit write by one rename(2), never by disk I/O.
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
    private let file: JSONDocumentFile<TimerSnapshot>
    var url: URL { file.url }

    init(url: URL) { file = JSONDocumentFile(url: url) }

    /// `<directory>/state.json`.
    convenience init(directory: URL) {
        self.init(url: directory.appending(path: "state.json", directoryHint: .notDirectory))
    }

    /// The saved snapshot, or nil if there is none. A file that cannot be decoded is moved aside
    /// (`state.json.corrupt-<time>-<id>`) and logged, so a bad write never blocks the timer; a file from a newer
    /// version is ignored but kept.
    func load() -> TimerSnapshot? {
        do {
            guard case .loaded(let snapshot) = try file.load() else { return nil }
            guard snapshot.version <= TimerSnapshot.currentVersion else {
                log.error("state.json has newer version \(snapshot.version, privacy: .public); ignoring it")
                return nil
            }
            return snapshot
        } catch {
            log.error("cannot read state.json: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Writes `snapshot` atomically unless a newer sequence number is already on disk. Returns whether it wrote.
    @discardableResult func write(_ snapshot: TimerSnapshot, sequence: Int) throws -> Bool {
        try file.write(snapshot, revision: sequence)
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
