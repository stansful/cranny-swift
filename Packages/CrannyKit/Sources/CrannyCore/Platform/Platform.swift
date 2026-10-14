// CrannyCore/Platform/Platform.swift
// Logging, haptics, file locations, version info.
import AppKit
import Foundation
import os

// MARK: - Logging

public nonisolated enum LogCategory: String, Sendable, CaseIterable {
    case app, overlay, state, input, activities, settings, permissions, storage, updates, onboarding
    case media, mediaBridge, calendar, quickApps, mirror, notes, todos, timer, tray, pipelines
    case hud, eventTap, system, bluetooth, effects
}

/// `private let log = Log.logger(.timer)` at file scope. Interpolate user data with `privacy: .private`
/// (titles, file names, paths); states, counts and error codes with `privacy: .public`.
public nonisolated enum Log {
    public static let subsystem = "app.cranny.Cranny"
    public static func logger(_ category: LogCategory) -> Logger { Logger(subsystem: subsystem, category: category.rawValue) }
}

// MARK: - Haptics (DESIGN.md §14.2)

public nonisolated enum HapticPattern: Sendable {
    case alignment      // threshold crossed, drop zone armed, snap, tutorial step
    case levelChange    // detents: scrubber 10 %, timer minute, HUD at 0/100 %
    case generic        // drop accepted, pipeline done, to-do completed, opened by gesture
}

/// Never for hover, peek or an activity arriving. Every haptic has a visual counterpart.
@MainActor public final class Haptics {
    private let isEnabled: @MainActor () -> Bool
    public init(isEnabled: @escaping @MainActor () -> Bool) { self.isEnabled = isEnabled }
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
    public let root: URL
    public let caches: URL
    public init(root: URL, caches: URL) { self.root = root; self.caches = caches }

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
    public func cacheDirectory(for module: ModuleID) throws -> URL {
        let url = caches.appending(path: module.rawValue, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

/// Codable document on disk with atomic writes. Corrupt files are renamed aside and the default is used.
public actor JSONFileStore<Value: Codable & Sendable> {
    public let url: URL
    private let defaultValue: Value
    public init(url: URL, defaultValue: Value) { self.url = url; self.defaultValue = defaultValue }

    public func load() -> Value {
        guard let data = try? Data(contentsOf: url) else { return defaultValue }
        do { return try JSONDecoder().decode(Value.self, from: data) } catch {
            let aside = url.appendingPathExtension("corrupt-\(Int(Date().timeIntervalSince1970))")
            try? FileManager.default.moveItem(at: url, to: aside)
            Log.logger(.storage).error("corrupt \(self.url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return defaultValue
        }
    }

    public func save(_ value: Value) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(value).write(to: url, options: .atomic)
    }
}

// MARK: - App info and versions

public nonisolated struct AppInfo: Sendable, Codable {
    public let bundleIdentifier: String
    public let version: String
    public let build: String
    public static func current(_ bundle: Bundle = .main) -> AppInfo {
        AppInfo(bundleIdentifier: bundle.bundleIdentifier ?? "(none)",
                version: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0",
                build: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0")
    }
}

/// "v1.2" / "1.10.0" / "1.2.0-beta.1" (pre-release suffix sorts before the release).
public nonisolated struct SemanticVersion: Comparable, Sendable, CustomStringConvertible {
    public let major: Int, minor: Int, patch: Int
    public let prerelease: String?
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
    public static func < (a: Self, b: Self) -> Bool {
        if (a.major, a.minor, a.patch) != (b.major, b.minor, b.patch) { return (a.major, a.minor, a.patch) < (b.major, b.minor, b.patch) }
        switch (a.prerelease, b.prerelease) {
        case (nil, _): return false
        case (_, nil): return true
        case let (x?, y?): return x.compare(y, options: .numeric) == .orderedAscending
        }
    }
    public var description: String { "\(major).\(minor).\(patch)" + (prerelease.map { "-\($0)" } ?? "") }
}
