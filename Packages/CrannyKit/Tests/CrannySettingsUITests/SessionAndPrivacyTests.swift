import CoreGraphics
import CrannyCore
import CrannyNotchUI
import Foundation
import Testing
@testable import CrannySettingsUI

// MARK: - The window's session (ARCHITECTURE §10.15: deep links; DESIGN.md §11.3: Reset All with a 10-s Undo)

/// Opening another pane, or a row of the same pane, navigates the window's state instead of rebuilding it, so the
/// Undo offer of Reset All survives a deep link or a ⌘K pane command.
@Test func openingAPaneKeepsTheUndoOffer() {
    let registry = ModuleRegistry(services: .preview())
    let session = SettingsSession(registry: registry, initialPage: .general)
    let stage = session.stage
    session.resetAll.resetAll()
    #expect(session.resetAll.canUndo)

    session.open(.appearance)
    #expect(session.currentPage == .appearance && session.resetAll.canUndo && session.stage === stage)

    let serial = session.navigator.highlightSerial
    session.open("appearance#motion")                                            // the same pane, a row in it
    #expect(session.currentPage == .appearance && session.navigator.highlightSerial == serial + 1)
    #expect(session.navigator.takePendingRow(in: .appearance) == "appearance.motion")
    session.open(nil)                                                            // nil keeps the pane
    #expect(session.currentPage == .appearance && session.resetAll.canUndo)
    session.resetAll.dismiss()
}

@Test func theSessionStartsOnItsPaneWithThatPanesStage() {
    let registry = ModuleRegistry(services: .preview())
    #expect(SettingsSession(registry: registry).currentPage == .general)
    let activities = SettingsSession(registry: registry, initialPage: "activities#satellite")
    #expect(activities.currentPage == .liveActivities)
    if SettingsQAOptions.stageState == nil { #expect(activities.stage.state == .activity) }
}

/// Closing the window releases its views, not the session: the stage stops (no view may be left to stop it) and lets
/// go of the wallpaper miniature, decoded again when the stage next appears; the pane, the search, the sidebar's pick
/// and the Undo offer stay, and the banner of a rebuilt window does not announce the offer to VoiceOver again.
@Test func closingTheWindowKeepsTheSessionAndDropsTheWallpaper() async throws {
    let registry = ModuleRegistry(services: .preview())
    let session = SettingsSession(registry: registry, initialPage: "appearance#motion")
    #expect(session.query == (SettingsQAOptions.search ?? "") && session.sidebarSelection == .pane(.appearance))
    session.query = "motion"
    session.resetAll.resetAll()
    #expect(session.resetAll.takeAnnouncement())                                 // the banner's first appearance
    let context = try #require(CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0,
                                         space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    session.stage.wallpaper = WallpaperSource.Miniature(image: try #require(context.makeImage()), topIsLight: false)
    session.stage.start()

    session.windowDidClose()
    #expect(session.stage.wallpaper == nil)
    #expect(session.currentPage == .appearance && session.query == "motion" && session.sidebarSelection == .pane(.appearance))
    #expect(session.resetAll.canUndo && !session.resetAll.takeAnnouncement())
    registry.services.settings[CoreSettings.density] = .roomy                   // a stopped stage follows nothing
    try await Task.sleep(for: .milliseconds(100))
    #expect(session.stage.model.theme.density != .roomy)

    session.resetAll.dismiss()
    session.resetAll.resetAll()                                                  // a new offer is announced again
    #expect(session.resetAll.takeAnnouncement())
    session.resetAll.dismiss()
}

/// The search index is built for a query and reused until what it indexes changes.
@Test func theSearchIndexIsBuiltOncePerChange() {
    let registry = ModuleRegistry(services: .preview())
    let pages = SettingsRootView.pages(registry: registry)
    let cache = SearchIndexCache()
    var builds = 0
    func rows() -> [SettingsRowInfo] { builds += 1; return ShellPanes.rows(registry: registry) }
    _ = cache.index(pages: pages, signature: ["a"], rows: rows)
    _ = cache.index(pages: pages, signature: ["a"], rows: rows)
    #expect(builds == 1)
    let index = cache.index(pages: pages, signature: ["b"], rows: rows)
    #expect(builds == 2)
    #expect(index.search("motion").rows.contains { $0.id == "appearance.motion" })
}

// MARK: - Shortcut recorders

@Test func startingARecorderStopsTheOneListening() {
    let recording = ShortcutRecording()
    let first = UUID(), second = UUID()
    var stopped: [UUID] = []
    recording.begin(first) { stopped.append(first); recording.end(first) }
    #expect(recording.activeID == first)
    recording.begin(second) { stopped.append(second); recording.end(second) }
    #expect(stopped == [first] && recording.activeID == second)
    recording.end(first)                                                         // a late stop of the first changes nothing
    #expect(recording.activeID == second)
    recording.begin(second) { stopped.append(second) }                           // restarting the same one stops nobody
    #expect(stopped == [first])
    recording.end(second)
    #expect(recording.activeID == nil)
}

// MARK: - Privacy: what Settings may read without a prompt

@Test func otherAppsContainersAreProtected() {
    let home = URL(fileURLWithPath: "/Users/me", isDirectory: true)
    func safe(_ path: String) -> Bool {
        ProtectedLocations.isSafeToRead(URL(fileURLWithPath: path), home: home, ownBundleID: "app.cranny")
    }
    #expect(!safe("/Users/me/Library/Containers/com.other.app/Data/Pictures/w.jpg"))
    #expect(!safe("/Users/me/Library/Group Containers/group.com.other/w.jpg"))
    #expect(safe("/Users/me/Library/Containers/app.cranny/Data/w.jpg"))          // Cranny's own container
    #expect(safe("/Users/me/Library/ContainersOld/w.jpg"))                         // a prefix of a name is not the folder
}

/// A link outside the protected folders that points into one is refused, without reading the target.
@Test func symbolicLinksIntoProtectedFoldersAreRefused() throws {
    let fileManager = FileManager.default
    let root = fileManager.temporaryDirectory.appendingPathComponent("cranny-protected-\(UUID().uuidString)", isDirectory: true)
    let home = root.appendingPathComponent("home", isDirectory: true)
    defer { try? fileManager.removeItem(at: root) }
    let pictures = home.appendingPathComponent("Pictures", isDirectory: true)
    let downloads = home.appendingPathComponent("Downloads", isDirectory: true)
    try fileManager.createDirectory(at: pictures, withIntermediateDirectories: true)
    try fileManager.createDirectory(at: downloads, withIntermediateDirectories: true)
    try Data().write(to: pictures.appendingPathComponent("real.jpg"))
    try fileManager.createSymbolicLink(atPath: pictures.appendingPathComponent("wall.jpg").path, withDestinationPath: "../Downloads/wall.jpg")
    try fileManager.createSymbolicLink(atPath: pictures.appendingPathComponent("dl").path, withDestinationPath: downloads.path)
    try fileManager.createSymbolicLink(atPath: pictures.appendingPathComponent("ok.jpg").path, withDestinationPath: "real.jpg")
    try fileManager.createSymbolicLink(atPath: pictures.appendingPathComponent("loop").path, withDestinationPath: "loop")

    func safe(_ url: URL) -> Bool { ProtectedLocations.isSafeToRead(url, home: home, ownBundleID: nil) }
    #expect(!safe(pictures.appendingPathComponent("wall.jpg")))                   // relative link to a file in Downloads
    #expect(!safe(pictures.appendingPathComponent("dl/wall.jpg")))                // a linked folder
    #expect(safe(pictures.appendingPathComponent("ok.jpg")))                      // a link that stays outside
    #expect(safe(pictures.appendingPathComponent("real.jpg")))
    #expect(!safe(pictures.appendingPathComponent("loop/w.jpg")))                 // a loop is given up on
    #expect(!safe(downloads.appendingPathComponent("w.jpg")))
}

// App names and icons: CrannyCore's AppIdentityTests (the resolver Settings uses).

@Test func systemShortcutsLoadOffTheMainActor() async {
    let loaded = await SystemShortcuts.load()
    #expect(!SystemShortcuts.knownDefaults.isEmpty)
    #expect(loaded.count >= 1)                                                   // the domain's entries, or the defaults
}
