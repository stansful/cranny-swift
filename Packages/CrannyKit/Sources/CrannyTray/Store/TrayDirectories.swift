// CrannyTray/Store/TrayDirectories.swift — the folders the Tray reads and writes (ARCHITECTURE.md §7.8): the copies and
// index, the pipelines' scratch space, the folders whose files are temporary, and Downloads for results.
import CrannyCore
import Foundation

/// The folders the Tray uses. `live(paths:)` in the app; temporary ones in tests and previews.
nonisolated struct TrayDirectories: Sendable, Equatable {
    /// Copies and `index.json`.
    var root: URL
    /// Scratch space for pipeline runs and staged drops (emptied after each use and on quit).
    var work: URL
    /// Files under these are temporary: always copied, never written next to.
    var temporaryRoots: [URL]
    /// Results of tray-owned files.
    var downloads: URL

    /// No I/O: folders are created on first use (ARCHITECTURE.md §3.4, `register` stays cheap).
    static func live(paths: AppPaths) -> TrayDirectories {
        let fm = FileManager.default
        let caches = paths.caches.appending(path: ModuleID.tray.rawValue, directoryHint: .isDirectory)
        let screenshots = fm.homeDirectoryForCurrentUser.appending(path: "Library/Containers/com.apple.screencaptureui",
                                                                   directoryHint: .isDirectory)
        return TrayDirectories(
            root: paths.root.appending(path: ModuleID.tray.rawValue, directoryHint: .isDirectory),
            work: caches.appending(path: "Work", directoryHint: .isDirectory),
            temporaryRoots: [caches, fm.temporaryDirectory, screenshots],
            downloads: fm.urls(for: .downloadsDirectory, in: .userDomainMask).first
                ?? fm.homeDirectoryForCurrentUser.appending(path: "Downloads", directoryHint: .isDirectory))
    }

    /// Everything inside one throw-away folder (tests, previews, Debug QA samples).
    static func temporary(_ base: URL = FileManager.default.temporaryDirectory
        .appending(path: "cranny-tray-\(UUID().uuidString)", directoryHint: .isDirectory)) -> TrayDirectories {
        TrayDirectories(root: base.appending(path: "Tray"), work: base.appending(path: "Work"),
                        temporaryRoots: [base.appending(path: "Incoming")], downloads: base.appending(path: "Downloads"))
    }
}
