// CrannySettingsUI/Components/ProtectedLocations.swift — Settings never reads a file that macOS guards with a privacy
// prompt: Files & Folders (Desktop, Documents, Downloads, iCloud Drive, File Provider storage, removable and network
// volumes) and "data from other apps" (other apps' containers and group containers). No permission is requested
// except from an explicit button (ARCHITECTURE §10.15). Used for the wallpaper miniature and for app icons and names.
//
// Symbolic links are followed one component at a time, and only where reading a link cannot prompt: a link is read
// only after the path up to it has been found outside every protected place, and a link whose target lies inside one
// is refused without touching the target. So a wallpaper reached through `~/Pictures/wall.jpg → ~/Downloads/wall.jpg`
// is never read (tested). Paths are normalized as strings (".", ".."), never through APIs that consult the disk.
import Foundation

nonisolated enum ProtectedLocations {
    /// The most links followed before giving up (a loop, or a chain nobody needs).
    private static let maximumLinks = 16

    /// True when reading `url` cannot raise a privacy prompt: a local file outside the protected places, also after
    /// following its symbolic links. `ownBundleID`'s own container is not protected.
    static func isSafeToRead(_ url: URL, home: URL = FileManager.default.homeDirectoryForCurrentUser,
                             ownBundleID: String? = Bundle.main.bundleIdentifier,
                             fileManager: FileManager = .default) -> Bool {
        guard url.isFileURL else { return false }
        let homePath = normalized(home.path)
        let protected = ProtectedSet(home: resolved(homePath, fileManager: fileManager) { _ in false } ?? homePath,
                                     ownBundleID: ownBundleID)
        return resolved(normalized(url.path), fileManager: fileManager, refusing: protected.contains) != nil
    }

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
    static func normalized(_ path: String) -> String {
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
