// CrannyCore/Platform/ProtectedLocations.swift — Cranny never reads, on its own initiative, a file that macOS guards
// with a privacy prompt: Files & Folders (Desktop, Documents, Downloads, iCloud Drive, File Provider storage, removable
// and network volumes) and "data from other apps" (other apps' containers and group containers). No permission is
// requested except from an explicit button (ARCHITECTURE §10.15). Used for the Settings wallpaper miniature and for app
// names and icons (`AppIdentityResolver`: Settings, Media's player rows; Quick Apps' launcher icons).
//
// Symbolic links are followed one component at a time, and only where reading a link cannot prompt: a link is read
// only after the path up to it has been found outside every protected place, and a link whose target lies inside one
// is refused without touching the target. So a wallpaper reached through `~/Pictures/wall.jpg → ~/Downloads/wall.jpg`
// is never read (tested). Paths are normalized as strings (".", ".."), never through APIs that consult the disk.
//
// The places are those of the caller's `home` AND of the account's own home from the user database: the one macOS
// guards. `homeDirectoryForCurrentUser` follows `CFFIXED_USER_HOME`, which a QA run sets to an isolated folder, so the
// default `home` alone would leave the real Desktop, Documents and Downloads unguarded in such a run.
import Foundation

/// Whether reading a file could raise a privacy prompt. Pure string work plus symbolic-link reads that cannot prompt.
public nonisolated enum ProtectedLocations {
    /// The most links followed before giving up (a loop, or a chain nobody needs).
    private static let maximumLinks = 16

    /// True when reading `url` cannot raise a privacy prompt: a local file outside the protected places of `home` and
    /// of the account's own home (`accountHome`), also after following its symbolic links. `ownBundleID`'s own
    /// container is not protected.
    public static func isSafeToRead(_ url: URL, home: URL = FileManager.default.homeDirectoryForCurrentUser,
                             ownBundleID: String? = Bundle.main.bundleIdentifier,
                             fileManager: FileManager = .default) -> Bool {
        guard url.isFileURL else { return false }
        var homes = [normalized(home.path)]
        if let account = accountHome.map(normalized), !homes.contains(account) { homes.append(account) }
        let protected = homes.map { path in
            ProtectedSet(home: resolved(path, fileManager: fileManager) { _ in false } ?? path, ownBundleID: ownBundleID)
        }
        return resolved(normalized(url.path), fileManager: fileManager,
                        refusing: { path in protected.contains { $0.contains(path) } }) != nil
    }

    /// The account's home folder from the user database (the one macOS protects), whatever `CFFIXED_USER_HOME` says.
    static let accountHome: String? = {
        var entry = passwd()
        var result: UnsafeMutablePointer<passwd>?
        var buffer = [CChar](repeating: 0, count: 16_384)
        return buffer.withUnsafeMutableBufferPointer { storage -> String? in
            guard getpwuid_r(getuid(), &entry, storage.baseAddress, storage.count, &result) == 0, result != nil,
                  let directory = entry.pw_dir else { return nil }
            return String(cString: directory)
        }
    }()

    /// `path` with its symbolic links followed one component at a time, or nil when `refusing` turns down the path
    /// or a link's target (before anything inside it is read), or after too many links.
    private static func resolved(_ start: String, fileManager: FileManager, refusing: (String) -> Bool) -> String? {
        var path = start
        guard !refusing(path) else { return nil }
        var links = 0
        var index = 1                                   // components[0] is "/"
        while true {
            let components = (path as NSString).pathComponents
            guard index < components.count else { return path }
            let prefix = NSString.path(withComponents: Array(components[...index]))
            // Every prefix of an accepted path is outside the protected places, so reading this link cannot prompt.
            guard let destination = try? fileManager.destinationOfSymbolicLink(atPath: prefix) else {
                index += 1
                continue
            }
            links += 1
            guard links <= maximumLinks else { return nil }
            let parent = (prefix as NSString).deletingLastPathComponent
            let target = destination.hasPrefix("/") ? destination : parent + "/" + destination
            let rest = components.dropFirst(index + 1).joined(separator: "/")
            path = normalized(rest.isEmpty ? target : target + "/" + rest)
            guard !refusing(path) else { return nil }
            index = 1                                   // the target may sit behind links itself: check from the top
        }
    }

    /// An absolute path without empty, "." and ".." components (string work only).
    public static func normalized(_ path: String) -> String {
        var parts: [Substring] = []
        for part in path.split(separator: "/", omittingEmptySubsequences: true) {
            switch part {
            case ".": continue
            case "..": if !parts.isEmpty { parts.removeLast() }
            default: parts.append(part)
            }
        }
        return "/" + parts.joined(separator: "/")
    }

    /// The protected places for one home folder.
    private struct ProtectedSet {
        let folders: [String]
        let allowed: [String]

        init(home: String, ownBundleID: String?) {
            let inHome = ["Desktop", "Documents", "Downloads", "Library/Mobile Documents", "Library/CloudStorage",
                          "Library/Containers", "Library/Group Containers"].map { home + "/" + $0 }
            folders = inHome + ["/Volumes", "/Network", "/net", "/private/var/automount"]
            allowed = ownBundleID.map { [home + "/Library/Containers/" + $0] } ?? []
        }

        func contains(_ path: String) -> Bool {
            func inside(_ folder: String) -> Bool { path == folder || path.hasPrefix(folder + "/") }
            if allowed.contains(where: inside) { return false }
            return folders.contains(where: inside)
        }
    }
}
