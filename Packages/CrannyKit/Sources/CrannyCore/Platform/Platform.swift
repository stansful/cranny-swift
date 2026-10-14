// CrannyCore/Platform/Platform.swift
// Logging, haptics, file locations, version info.
import AppKit
import Foundation
import os

// MARK: - Logging

/// One `Logger` category per area (Console: subsystem app.cranny.Cranny).
public nonisolated enum LogCategory: String, Sendable, CaseIterable {
    case app, overlay, state, input, activities, settings, permissions, storage, updates, onboarding
    case media, mediaBridge, calendar, quickApps, mirror, notes, todos, timer, tray, pipelines
    case hud, eventTap, system, bluetooth, effects
}

/// `private let log = Log.logger(.timer)` at file scope. Interpolate user data with `privacy: .private`
/// (titles, file names, paths); states, counts and error codes with `privacy: .public`.
public nonisolated enum Log {
    /// The logging subsystem (also the app's support folder name).
    public static let subsystem = "app.cranny.Cranny"
    /// A logger for `category`.
    public static func logger(_ category: LogCategory) -> Logger { Logger(subsystem: subsystem, category: category.rawValue) }
}

// MARK: - Haptics (DESIGN.md §14.2)

/// The three haptic patterns Cranny uses (DESIGN.md §14.2).
public nonisolated enum HapticPattern: Sendable {
    case alignment      // threshold crossed, drop zone armed, snap, tutorial step
    case levelChange    // detents: scrubber 10 %, timer minute, HUD at 0/100 %
    case generic        // drop accepted, pipeline done, to-do completed, opened by gesture
}

/// Never for hover, peek or an activity arriving. Every haptic has a visual counterpart.
@MainActor public final class Haptics {
    private let isEnabled: @MainActor () -> Bool
    /// Haptics that play only while `isEnabled()` (Gestures ▸ Haptic feedback).
    public init(isEnabled: @escaping @MainActor () -> Bool) { self.isEnabled = isEnabled }
    /// Plays `pattern` now (felt only while a finger is on a Force Touch trackpad).
    public func play(_ pattern: HapticPattern) {
        guard isEnabled() else { return }
        let p: NSHapticFeedbackManager.FeedbackPattern = switch pattern {
        case .alignment: .alignment
        case .levelChange: .levelChange
        case .generic: .generic
        }
        NSHapticFeedbackManager.defaultPerformer.perform(p, performanceTime: .now)
    }
}

// MARK: - Files

/// ~/Library/Application Support/app.cranny.Cranny/<module>/ — the only place modules write files.
public nonisolated struct AppPaths: Sendable {
    /// Application Support/app.cranny.Cranny: module content (`directory(for:)`).
    public let root: URL
    /// Caches/app.cranny.Cranny: rebuildable data (`cacheDirectory(for:)`).
    public let caches: URL
    /// Paths under explicit roots.
    public init(root: URL, caches: URL) { self.root = root; self.caches = caches }

    /// The user's real folders (the app; never in tests or previews).
    public static let live: AppPaths = {
        let fm = FileManager.default
        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let caches = fm.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return AppPaths(root: support.appending(path: Log.subsystem, directoryHint: .isDirectory),
                        caches: caches.appending(path: Log.subsystem, directoryHint: .isDirectory))
    }()

    /// A fresh throw-away root for tests and previews.
    public static func temporary() -> AppPaths {
        let base = FileManager.default.temporaryDirectory.appending(path: "cranny-\(UUID().uuidString)", directoryHint: .isDirectory)
        return AppPaths(root: base.appending(path: "Support"), caches: base.appending(path: "Caches"))
    }

    /// Creates the directory on first use.
    public func directory(for module: ModuleID) throws -> URL {
        let url = root.appending(path: module.rawValue, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    /// The module's cache folder, created on first use.
    public func cacheDirectory(for module: ModuleID) throws -> URL {
        let url = caches.appending(path: module.rawValue, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

/// A Codable document on disk with a default value, for caches and indexes that can be rebuilt (the update cache, the
/// Tray index). Built on `JSONDocumentFile`: a missing file reads as the default; a corrupt one is set aside under a
/// unique name and reads as the default; a file that exists but cannot be READ (permissions, I/O) also reads as the
/// default, but then every `save` throws `JSONFileStoreError.unreadableFile` instead of replacing it. Saves are
/// atomic and serialized by the actor in call order. Content the user made (notes, to-dos) uses `JSONDocumentFile`
/// directly, which also has a synchronous write for `applicationWillTerminate`.
public actor JSONFileStore<Value: Codable & Sendable> {
    /// The document's location.
    public nonisolated var url: URL { file.url }
    private let file: JSONDocumentFile<Value>
    private let defaultValue: Value
    private var revision = 0
    private var unreadable = false

    /// A store for `url` that reads as `defaultValue` until something is saved. No I/O happens here.
    public init(url: URL, defaultValue: Value) {
        self.file = JSONDocumentFile(url: url)
        self.defaultValue = defaultValue
    }

    /// The saved value, or `defaultValue` (missing, corrupt or unreadable file; see the type's documentation).
    public func load() -> Value {
        do {
            switch try file.load() {
            case .loaded(let value): unreadable = false; return value
            case .missing, .corrupt: unreadable = false; return defaultValue
            }
        } catch {
            unreadable = true
            Log.logger(.storage).error("cannot read \(self.url.lastPathComponent, privacy: .public), keeping it: \(error.localizedDescription, privacy: .public)")
            return defaultValue
        }
    }

    /// Writes `value` atomically. Throws `JSONFileStoreError.unreadableFile` after a `load()` that could not read an
    /// existing file (it is kept, never replaced by a default), and any encoding or file-system error.
    public func save(_ value: Value) throws {
        guard !unreadable else { throw JSONFileStoreError.unreadableFile(url) }
        revision += 1
        try file.write(value, revision: revision)
    }
}

/// Why a `JSONFileStore` did not save.
public nonisolated enum JSONFileStoreError: Error, Equatable, Sendable {
    /// The last `load()` found the file but could not read it; saving would replace it.
    case unreadableFile(URL)
}

// MARK: - App info and versions

/// Identity and version of a bundle (About, diagnostics, the update check).
public nonisolated struct AppInfo: Sendable, Codable {
    /// The bundle identifier, "(none)" if missing.
    public let bundleIdentifier: String
    /// CFBundleShortVersionString ("0.1.0").
    public let version: String
    /// CFBundleVersion.
    public let build: String
    /// The info of `bundle` (the app by default).
    public static func current(_ bundle: Bundle = .main) -> AppInfo {
        AppInfo(bundleIdentifier: bundle.bundleIdentifier ?? "(none)",
                version: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0",
                build: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0")
    }
}

/// "v1.2" / "1.10.0" / "1.2.0-beta.1" (pre-release suffix sorts before the release).
public nonisolated struct SemanticVersion: Comparable, Sendable, CustomStringConvertible {
    /// The numeric components (missing ones are 0).
    public let major: Int, minor: Int, patch: Int
    /// The part after "-" ("beta.1"), nil for a release.
    public let prerelease: String?
    /// Parses "1", "1.2", "v1.2.3" or "1.2.3-beta.1"; nil for anything else.
    public init?(_ string: String) {
        var s = Substring(string)
        if s.hasPrefix("v") { s = s.dropFirst() }
        let parts = s.split(separator: "-", maxSplits: 1)
        let nums = parts.first.map { $0.split(separator: ".").map { Int($0) } } ?? []
        guard (1...3).contains(nums.count), nums.allSatisfy({ $0 != nil }) else { return nil }
        let n = nums.compactMap { $0 } + [0, 0]
        (major, minor, patch) = (n[0], n[1], n[2])
        prerelease = parts.count > 1 ? String(parts[1]) : nil
    }
    /// Numeric order; a pre-release sorts before its release, pre-releases compare numerically.
    public static func < (a: Self, b: Self) -> Bool {
        if (a.major, a.minor, a.patch) != (b.major, b.minor, b.patch) { return (a.major, a.minor, a.patch) < (b.major, b.minor, b.patch) }
        switch (a.prerelease, b.prerelease) {
        case (nil, _): return false
        case (_, nil): return true
        case let (x?, y?): return x.compare(y, options: .numeric) == .orderedAscending
        }
    }
    /// "1.2.3" or "1.2.3-beta.1".
    public var description: String { "\(major).\(minor).\(patch)" + (prerelease.map { "-\($0)" } ?? "") }
}
