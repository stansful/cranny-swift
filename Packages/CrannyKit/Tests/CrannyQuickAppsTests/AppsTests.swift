// Apps: the running set (event-driven, no polling), resolution and drop inspection. Lookups are read-only
// (LaunchServices, Info.plist, icons); nothing is launched.
import AppKit
import CrannyCore
import Foundation
import Testing
@testable import CrannyQuickApps

@Test func runningCountsInstances() {
    var running = RunningApps(["a", "a", "b"])
    #expect(running.contains("a") && running.contains("b"))
    running.terminated("a")
    #expect(running.contains("a"))
    running.terminated("a")
    #expect(!running.contains("a"))
    running.terminated("never")
    running.launched("c")
    #expect(running.contains("c"))
}

@Test func runningDotsFollowWorkspaceNotifications() async throws {
    // Any app that is running now (Finder, Dock…) stands in for the launched one; the centre is private.
    let app = try #require(NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier != nil })
    let id = try #require(app.bundleIdentifier)
    let center = NotificationCenter()
    let observer = RunningAppsObserver(center: center, snapshot: { [] })
    var launches: [String] = []
    observer.onLaunch = { launches.append($0) }
    observer.start()
    #expect(!observer.isRunning(id))

    center.post(name: NSWorkspace.didLaunchApplicationNotification, object: nil, userInfo: [NSWorkspace.applicationUserInfoKey: app])
    #expect(await waitUntil { observer.isRunning(id) })
    #expect(launches == [id])

    center.post(name: NSWorkspace.didTerminateApplicationNotification, object: nil, userInfo: [NSWorkspace.applicationUserInfoKey: app])
    #expect(await waitUntil { !observer.isRunning(id) })

    observer.stop()
    center.post(name: NSWorkspace.didLaunchApplicationNotification, object: nil, userInfo: [NSWorkspace.applicationUserInfoKey: app])
    try await Task.sleep(for: .milliseconds(50))
    #expect(!observer.isRunning(id))                                  // unsubscribed
}

@Test func runningSnapshotAtStart() {
    let observer = RunningAppsObserver(center: NotificationCenter(), snapshot: { ["com.apple.finder"] })
    #expect(!observer.isRunning("com.apple.finder"))                 // nothing before start (register is cheap)
    observer.start()
    #expect(observer.isRunning("com.apple.finder"))
    observer.stop()
}

@Test func catalogSplitsInstalledAndMissing() async {
    let catalog = AppCatalog(resolver: FakeResolver(["a", "b"]))
    #expect(!catalog.hasResolved)
    await catalog.refresh(["a", "b", "gone", "a"])
    #expect(catalog.hasResolved)
    #expect(catalog.app("a")?.bundleID == "a")
    #expect(catalog.app("gone") == nil)
    #expect(catalog.isMissing("gone"))
    #expect(!catalog.isMissing("a"))
}

@Test func catalogFindsAppsAmongDroppedFiles() async {
    let catalog = AppCatalog(resolver: FakeResolver([]))
    let urls = ["/x/a.app", "/x/readme.txt", "/y/a.app", "/x/b.app"].map { URL(fileURLWithPath: $0) }
    #expect(await catalog.apps(at: urls).map(\.bundleID) == ["a", "b"])
}

@Test func workspaceResolverReadsAnAppBundle() async throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: "cranny-quickapps-\(UUID().uuidString)", directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: directory) }
    let app = directory.appending(path: "Fake Tool.app", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: app.appending(path: "Contents"), withIntermediateDirectories: true)
    let plist: [String: Any] = ["CFBundleIdentifier": "app.cranny.tests.fake-tool", "CFBundleName": "Fake Tool", "CFBundlePackageType": "APPL"]
    try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        .write(to: app.appending(path: "Contents/Info.plist"))
    let text = directory.appending(path: "notes.txt")
    try Data("hi".utf8).write(to: text)

    let resolver = WorkspaceAppResolver()
    let found = try #require(await resolver.app(at: app))
    #expect(found.bundleID == "app.cranny.tests.fake-tool")
    #expect(found.name == "Fake Tool")
    #expect(await resolver.app(at: text) == nil)
    #expect(await resolver.app(at: directory) == nil)
}

@Test func workspaceResolverFindsSystemAppsAndTheirIcons() async throws {
    let resolver = WorkspaceAppResolver()
    let finder = try #require(await resolver.resolve("com.apple.finder"))
    #expect(finder.url.lastPathComponent == "Finder.app")
    let core = try #require(await AppIdentityResolver.locate("com.apple.finder"))      // CrannyCore's lookup and name
    #expect(finder.url == core.url && finder.name == core.name && finder.name != "com.apple.finder")
    #expect(await resolver.resolve("app.cranny.tests.not-installed") == nil)
    let icon = try #require(await resolver.icon(at: finder.url, pixelSize: 64))
    #expect(icon.width == 64)
}

@Test func anAddedAppLaunchServicesDoesNotKnowYetStays() async {
    // "fresh" is not registered (resolve fails) but its bundle is where the drop found it.
    let catalog = AppCatalog(resolver: FakeResolver([]))
    catalog.insert(FakeResolver.app("fresh"))
    await catalog.refresh(["fresh", "gone"])
    #expect(catalog.app("fresh") != nil)
    #expect(catalog.isMissing("gone"))
}

/// Quick Apps reads CrannyCore's explicit app state (§10.20 #11): not looked up yet, installed, or looked up and not
/// found; an app installed meanwhile turns up on the next refresh.
@Test func catalogKnowsWhetherAnAppIsLookedUpInstalledOrNotInstalled() async {
    let resolver = FakeResolver(["a"])
    let catalog = AppCatalog(resolver: resolver)
    #expect(catalog.presence("a") == .pending && catalog.presence("gone") == .pending)
    await catalog.refresh(["a", "gone"])
    #expect(catalog.presence("a") == .installed && catalog.presence("gone") == .notInstalled)
    #expect(catalog.presence("added") == .pending)                    // in the list, not looked up yet
    resolver.install("gone")
    await catalog.refresh(["a", "gone"])
    #expect(catalog.presence("gone") == .installed)
}

/// Settings ▸ Shortcuts never shows a bundle identifier: an app's Finder name, "App not installed" once the lookup
/// found nothing (in the title; no second line), and no name while the lookup runs.
@Test func settingsRowsNeverShowABundleIdentifier() async {
    let catalog = AppCatalog(resolver: FakeResolver(["com.example.here"]))
    let gone = TileSettingsRow.Row.app(bundleID: "com.example.gone", app: nil)
    #expect(gone.title(in: catalog).isEmpty && !gone.isMissing(in: catalog))            // still looking it up
    #expect(gone.subtitle(in: catalog) != nil)

    await catalog.refresh(["com.example.here", "com.example.gone"])
    let title = gone.title(in: catalog)
    #expect(["App not installed", "Приложение не установлено"].contains(title))           // the test runs in either
    #expect(gone.isMissing(in: catalog) && gone.subtitle(in: catalog) == nil)
    let here = TileSettingsRow.Row.app(bundleID: "com.example.here", app: catalog.app("com.example.here"))
    #expect(here.title(in: catalog) == "here" && !here.isMissing(in: catalog))
    for row in [gone, here] { #expect(!row.title(in: catalog).contains("com.example")) }
}

/// No icon is read from a protected folder (CrannyCore's `ProtectedLocations`, as for Settings' app rows): an app left
/// in Downloads gets macOS's generic app icon, so the launcher raises no Files & Folders prompt. String work only: no
/// protected folder is touched (the home folder is a temporary one).
@Test func noIconIsReadFromAProtectedFolder() async throws {
    let home = FileManager.default.temporaryDirectory.appending(path: "cranny-home-\(UUID().uuidString)", directoryHint: .isDirectory)
    let isSafe: (URL) -> Bool = { ProtectedLocations.isSafeToRead($0, home: home) }
    let downloaded = home.appending(path: "Downloads/Spotify.app", directoryHint: .isDirectory)
    #expect(WorkspaceAppResolver.iconSource(for: downloaded, isSafeToRead: isSafe) == .genericApp)
    let finder = URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app", isDirectory: true)
    #expect(WorkspaceAppResolver.iconSource(for: finder, isSafeToRead: isSafe) == .bundle(finder))
    #expect(WorkspaceAppResolver.iconSource(for: finder, isSafeToRead: { _ in false }) == .genericApp)
}
