// CrannySettingsUI/Components/ProtectedLocations.swift — Settings never reads a file that macOS guards with a
// Files & Folders prompt (Desktop, Documents, Downloads, iCloud Drive, File Provider storage, removable and network
// volumes): no permission is requested except from an explicit button (ARCHITECTURE §10.15). A pure path check
// that never touches the file system (tested). Used for the wallpaper miniature and for app icons and names.
import Foundation

enum ProtectedLocations {
    /// True when reading `url` cannot raise a Files & Folders prompt: a local file outside the protected folders.
    static func isSafeToRead(_ url: URL, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> Bool {
        guard url.isFileURL else { return false }
        let path = url.standardizedFileURL.path
        let homePath = home.standardizedFileURL.path
        let protectedInHome = ["Desktop", "Documents", "Downloads", "Library/Mobile Documents", "Library/CloudStorage"]
            .map { homePath + "/" + $0 }
        let protectedRoots = ["/Volumes", "/Network", "/net", "/private/var/automount"]
        for folder in protectedInHome + protectedRoots where path == folder || path.hasPrefix(folder + "/") {
            return false
        }
        return true
    }
}
