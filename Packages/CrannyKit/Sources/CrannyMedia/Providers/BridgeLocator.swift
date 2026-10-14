// CrannyMedia/Providers/BridgeLocator.swift — finds libCrannyMediaBridge.dylib and makes sure perl can load
// it without a Gatekeeper prompt (ARCHITECTURE.md §6.3). File I/O only: call it off the main actor.
//
// Integrity: the quarantine copy lives in Application Support, which any process of the user can write. It is
// compared byte for byte with the app's own library (and must be a regular file Cranny wrote, not a link) every
// time a helper is about to be spawned — `BridgeResolution` locates again before every provider start and restart —
// and rewritten when it differs. The `CRANNY_MEDIA_BRIDGE` override exists in Debug builds only (integration
// tests): a Release build never loads a library named by its launch environment.
import CrannyCore
import Darwin
import Foundation
import os

private nonisolated let log = Log.logger(.mediaBridge)

nonisolated enum BridgeLocator {
    static let fileName = "libCrannyMediaBridge.dylib"
    static let environmentOverride = "CRANNY_MEDIA_BRIDGE"
    static let quarantineAttribute = "com.apple.quarantine"

    /// Candidate locations in order: `CRANNY_MEDIA_BRIDGE` (Debug builds only) → `Contents/Frameworks` → next to
    /// the executable (SwiftPM tools and tests). Pure: no file system access.
    static func candidates(environment: [String: String], privateFrameworks: URL?, executable: URL?) -> [URL] {
        var urls: [URL] = []
        #if DEBUG
        if let override = environment[environmentOverride], !override.isEmpty {
            urls.append(URL(fileURLWithPath: override))
        }
        #endif
        if let privateFrameworks { urls.append(privateFrameworks.appending(path: fileName)) }
        if let executable { urls.append(executable.deletingLastPathComponent().appending(path: fileName)) }
        return urls
    }

    /// The first candidate that exists; a quarantined one is replaced by an unquarantined copy in
    /// `copyDirectory` (files Cranny writes itself are not quarantined). nil = no bridge available.
    static func locate(candidates: [URL], copyDirectory: () throws -> URL) -> URL? {
        let fm = FileManager.default
        guard let found = candidates.first(where: { fm.fileExists(atPath: $0.path) }) else {
            log.error("bridge dylib not found (\(candidates.count, privacy: .public) candidates)")
            return nil
        }
        guard isQuarantined(found) else { return found }
        do {
            return try unquarantinedCopy(of: found, in: copyDirectory())
        } catch {
            log.error("bridge dylib is quarantined and could not be copied: \(error.localizedDescription, privacy: .private)")
            return found          // perl may show a Gatekeeper prompt; the handshake watchdog catches a hang
        }
    }

    /// The default search for the running app.
    static func locateForApp(paths: AppPaths) -> URL? {
        locate(candidates: candidates(environment: ProcessInfo.processInfo.environment,
                                      privateFrameworks: Bundle.main.privateFrameworksURL,
                                      executable: Bundle.main.executableURL),
               copyDirectory: { try paths.directory(for: .media) })
    }

    static func isQuarantined(_ url: URL) -> Bool {
        url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return false }
            return getxattr(path, quarantineAttribute, nil, 0, 0, 0) >= 0
        }
    }

    /// Copies the bytes (not the extended attributes) unless an identical, unquarantined regular file is already
    /// there. Anything else at the destination (other bytes, a symbolic link, a quarantined file) is replaced: the
    /// atomic write renames a new file over it.
    static func unquarantinedCopy(of source: URL, in directory: URL) throws -> URL {
        let destination = directory.appending(path: fileName)
        let bytes = try Data(contentsOf: source)
        // `attributesOfItem` does not follow links: a link reads as `.typeSymbolicLink`, nothing there as nil.
        let existingType = (try? FileManager.default.attributesOfItem(atPath: destination.path))?[.type] as? FileAttributeType
        if existingType == .typeRegular, let existing = try? Data(contentsOf: destination), existing == bytes,
           !isQuarantined(destination) {
            return destination
        }
        if existingType == nil {
            log.info("bridge dylib is quarantined; using a copy in Application Support")
        } else {
            log.info("bridge dylib copy in Application Support differs from the app's; replacing it")
        }
        try bytes.write(to: destination, options: .atomic)
        _ = destination.withUnsafeFileSystemRepresentation { path in
            path.map { removexattr($0, quarantineAttribute, 0) }
        }
        return destination
    }
}
