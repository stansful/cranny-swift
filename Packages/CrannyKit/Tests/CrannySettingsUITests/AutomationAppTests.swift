import CrannyCore
import Foundation
import Testing
@testable import CrannySettingsUI

// MARK: - Settings ▸ Permissions: Automation rows name their app (ARCHITECTURE §10.20 issue 11)

@Test func automationAppsAreNamedLikeFinderNamesThem() {
    let spotify = URL(fileURLWithPath: "/Applications/Spotify.app")
    #expect(AutomationApp.resolve(nil) == .notInstalled)
    #expect(AutomationApp.resolve(spotify, isSafeToRead: { _ in true }, displayName: { _ in "Spotify" }) == .installed(name: "Spotify"))
    // In a protected folder the bundle is not read: its file name stands in.
    let downloaded = URL(fileURLWithPath: "/Users/me/Downloads/Spotify.app")
    #expect(AutomationApp.resolve(downloaded, isSafeToRead: { _ in false }, displayName: { _ in Issue.record("read"); return "" })
            == .installed(name: "Spotify"))
    // A bundle that names nothing never falls back to its identifier.
    #expect(AutomationApp.resolve(spotify, isSafeToRead: { _ in true }, displayName: { _ in "  " }) == .installed(name: "Spotify"))
}

/// The real lookup (Launch Services, off the main actor): an installed app has its name, an unknown one none.
@Test func automationLookupFindsInstalledAppsOnly() async {
    let finder = await AutomationApp.lookUp("com.apple.finder")
    #expect(finder.name.map { !$0.isEmpty && $0 != "com.apple.finder" && !$0.hasSuffix(".app") } == true)
    #expect(await AutomationApp.lookUp("com.example.cranny.not-installed") == .notInstalled)
}

/// Titles never carry a bundle identifier: an Automation row has none until its app is known to be installed.
@Test func automationRowsShowOnlyInstalledAppsByName() {
    let entries = PermissionEntry.entries([
        PermissionUse(kind: .calendar, module: .calendar, reason: "C"),
        PermissionUse(kind: .automation(bundleID: "com.apple.Music"), module: .media, reason: "M"),
        PermissionUse(kind: .automation(bundleID: "com.spotify.client"), module: .media, reason: "M"),
    ])
    let apps: [String: AutomationApp] = ["com.apple.Music": .installed(name: "Music"), "com.spotify.client": .notInstalled]
    let rows = PermissionsRows.shown(entries) { apps[$0] ?? .pending }
    #expect(rows.map(\.entry.id) == ["calendar", "automation.com.apple.Music"])
    #expect(rows[0].title == PermissionKind.calendar.title)
    #expect(rows[1].title.contains("Music") && !rows[1].title.contains("com.apple"))
    #expect(!PermissionsRows.isWaiting(entries) { apps[$0] ?? .pending })

    let waiting: (String) -> AutomationApp = { _ in .pending }
    #expect(PermissionsRows.shown(entries, app: waiting).map(\.entry.id) == ["calendar"])
    #expect(PermissionsRows.isWaiting(entries, app: waiting))
}

/// The cache answers `.pending` first, then the lookup's answer; a refresh picks up an app installed or removed
/// meanwhile, and the revision (the search index's signature) moves only when an answer changes.
@Test func automationAppsLookUpOnceAndRefresh() async {
    let installed = Locked(false)
    let apps = AutomationApps { _ in installed.value ? .installed(name: "Spotify") : .notInstalled }
    #expect(apps.app("com.spotify.client") == .pending)
    #expect(apps.app("com.spotify.client") == .pending && apps.isLookingUp)          // one lookup per app at a time
    await waitUntil { !apps.isLookingUp }
    #expect(apps.app("com.spotify.client") == .notInstalled)
    let revision = apps.revision

    apps.refresh()                                                                    // nothing changed
    #expect(apps.isLookingUp && apps.app("com.spotify.client") == .notInstalled)      // the row keeps its answer meanwhile
    await waitUntil { !apps.isLookingUp }
    #expect(apps.revision == revision)

    installed.value = true
    apps.refresh()
    await waitUntil { !apps.isLookingUp }
    #expect(apps.app("com.spotify.client") == .installed(name: "Spotify") && apps.revision == revision + 1)
}

/// Search offers exactly the Automation rows the pane shows.
@Test func searchOffersOnlyInstalledAutomationApps() async {
    let registry = ModuleRegistry(services: .preview())
    registry.declare(.automation(bundleID: "com.apple.Music"), reason: "M")
    registry.declare(.automation(bundleID: "com.spotify.client"), reason: "S")
    let apps = AutomationApps { $0 == "com.apple.Music" ? .installed(name: "Music") : .notInstalled }
    #expect(PermissionsRows.all(registry: registry, apps: apps).isEmpty)                  // both still pending
    await waitUntil { apps.revision == 2 }
    let rows = PermissionsRows.all(registry: registry, apps: apps)
    #expect(rows.map(\.id) == ["permissions.automation.com.apple.Music"])
    #expect(rows.allSatisfy { !$0.title.contains("com.") })
}

// MARK: - Helpers

/// A value the injected lookups read from another isolation domain.
private nonisolated final class Locked<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value
    init(_ value: Value) { stored = value }
    var value: Value {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}

/// Waits (at most 2 s) for `condition`, letting the cache's lookups land.
private func waitUntil(_ condition: () -> Bool) async {
    for _ in 0..<200 where !condition() { try? await Task.sleep(for: .milliseconds(10)) }
}
