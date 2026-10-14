// CrannyCore/Platform/JSONDocumentFile.swift
// One Codable document on disk, the way every content store needs it (To-dos, Timer, Notes' index, the Tray index,
// the update cache): a load that tells "missing" from "unreadable", corrupt files set aside under a unique name, atomic
// writes that a stale background save can never let overtake a newer one, and a synchronous path for
// `applicationWillTerminate`.
//
// Threading: a `Sendable` class without its own executor. The synchronous `load()` / `write(_:revision:)` run on the
// caller's thread (the terminate hook, tests); the `…InBackground` variants are `@concurrent` (never on the main actor,
// ARCHITECTURE.md §9.1). Writes are serialized by a lock that is held only for the compare-and-rename that publishes
// a staged file, never for encoding or disk writes.
//
// Energy: the `…InBackground` variants run at the calling task's priority, and a task started on the main actor is
// user-initiated. Start a save nobody waits on from a `.utility` task (`Task(priority: .utility)`, or
// `Debouncer(delay:priority:)`), so encoding and the write run on efficiency cores with throttled I/O.
import Darwin
import Foundation
import os

/// A JSON document at `url`. See the file header for the threading rules.
public nonisolated final class JSONDocumentFile<Value: Codable & Sendable>: Sendable {
    /// What `load()` found.
    public enum LoadOutcome: Sendable {
        /// The decoded document.
        case loaded(Value)
        /// There is no file yet (first launch).
        case missing
        /// The file could not be decoded; it was renamed to `movedTo` (kept for diagnosis), so nothing overwrites it.
        case corrupt(movedTo: URL)
    }

    /// How dates are written: Foundation's default (seconds since 2001) or ISO 8601 strings.
    public enum DateCoding: Sendable { case deferredToDate, iso8601 }

    /// The document's location. The parent directory is created by the first write.
    public let url: URL
    private let dateCoding: DateCoding
    /// The revision of the newest document on disk (`Int.min` before the first write).
    private let newestWritten = OSAllocatedUnfairLock(initialState: Int.min)

    /// A document at `url`; no I/O happens here.
    public init(url: URL, dateCoding: DateCoding = .deferredToDate) {
        self.url = url
        self.dateCoding = dateCoding
    }

    // MARK: Reading

    /// Reads and decodes the document. A missing file is `.missing`; a file that cannot be decoded is renamed aside
    /// (`<name>.corrupt-<seconds>-<8 hex>`) and reported as `.corrupt`. Throws when the file exists but cannot be read
    /// (permissions, I/O) or cannot be moved aside: the caller must then not save over it, because the file may hold
    /// the user's only copy.
    public func load() throws -> LoadOutcome {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return .missing
        }
        let decodingError: any Error
        do {
            return .loaded(try decoder.decode(Value.self, from: data))
        } catch {
            decodingError = error
        }
        let aside = Self.asideURL(for: url)
        do {
            try FileManager.default.moveItem(at: url, to: aside)
        } catch {
            Log.logger(.storage).error("corrupt \(self.url.lastPathComponent, privacy: .public) cannot be moved aside, keeping it: \(error.localizedDescription, privacy: .public)")
            throw error
        }
        Log.logger(.storage).error("corrupt \(self.url.lastPathComponent, privacy: .public), moved aside to \(aside.lastPathComponent, privacy: .public): \(decodingError.localizedDescription, privacy: .public)")
        return .corrupt(movedTo: aside)
    }

    /// `load()` off the main actor.
    @concurrent public func loadInBackground() async throws -> LoadOutcome { try load() }

    /// `<name>.corrupt-<seconds>-<8 hex>`: unique, so a second corrupt file in the same second (a retry) never
    /// collides with the first one's copy.
    public static func asideURL(for url: URL, date: Date = Date()) -> URL {
        let suffix = UUID().uuidString.prefix(8).lowercased()
        return url.appendingPathExtension("corrupt-\(Int(date.timeIntervalSince1970))-\(suffix)")
    }

    // MARK: Writing

    /// Writes `value` atomically unless a document with a newer (or the same) `revision` is already on disk; returns
    /// whether it wrote. Callers number their snapshots in the order they took them (on the main actor), so a slow
    /// background save can never replace the synchronous flush at quit. The bytes are staged in a temporary file next
    /// to the document with no lock held; only the compare-and-rename runs under the lock.
    @discardableResult
    public func write(_ value: Value, revision: Int) throws -> Bool {
        guard newestWritten.withLock({ revision > $0 }) else { return false }        // already superseded: no I/O
        let data = try encoder.encode(value)
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // Same directory as the target, so the rename stays on one volume and is atomic.
        let staged = directory.appending(path: ".\(url.lastPathComponent).\(UUID().uuidString).tmp", directoryHint: .notDirectory)
        try data.write(to: staged)
        var published = false
        defer { if !published { try? FileManager.default.removeItem(at: staged) } }
        let url = self.url
        published = try newestWritten.withLock { newest in
            guard revision > newest else { return false }                          // a newer write won meanwhile
            guard rename(staged.path, url.path) == 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            newest = revision
            return true
        }
        return published
    }

    /// `write(_:revision:)` off the main actor, at the calling task's priority (see the file header).
    @discardableResult
    @concurrent public func writeInBackground(_ value: Value, revision: Int) async throws -> Bool {
        try write(value, revision: revision)
    }

    // MARK: Coding

    private var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if dateCoding == .iso8601 { encoder.dateEncodingStrategy = .iso8601 }
        return encoder
    }

    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        if dateCoding == .iso8601 { decoder.dateDecodingStrategy = .iso8601 }
        return decoder
    }
}

extension JSONDocumentFile.LoadOutcome: Equatable where Value: Equatable {}
