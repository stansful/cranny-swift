import CrannyCore
import Foundation
import Testing
@testable import CrannySettingsUI

// MARK: - Settings ▸ Permissions: Automation rows name their app (ARCHITECTURE §10.20 issue 11)
// Naming and lookups are CrannyCore's `AppIdentityResolver` (its tests: AppIdentityTests); these check the rows.

private func installed(_ id: String, _ name: String) -> AppIdentity {
    AppIdentity(bundleID: id, presence: .installed, name: name, url: URL(fileURLWithPath: "/Applications/\(name).app"))
}

/// Titles never carry a bundle identifier: an Automation row has none until its app is known to be installed.
@Test func automationRowsShowOnlyInstalledAppsByName() {
    let entries = PermissionEntry.entries([
        PermissionUse(kind: .calendar, module: .calendar, reason: "C"),
        PermissionUse(kind: .automation(bundleID: "com.apple.Music"), module: .media, reason: "M"),
        PermissionUse(kind: .automation(bundleID: "com.spotify.client"), module: .media, reason: "M"),
    ])
    let apps: [String: AppIdentity] = [
        "com.apple.Music": installed("com.apple.Music", "Music"),
        "com.spotify.client": AppIdentity(bundleID: "com.spotify.client", presence: .notInstalled),
    ]
    let known: (String) -> AppIdentity = { apps[$0] ?? AppIdentity(bundleID: $0) }
    let rows = PermissionsRows.shown(entries, app: known)
    #expect(rows.map(\.entry.id) == ["calendar", "automation.com.apple.Music"])
    #expect(rows[0].title == PermissionKind.calendar.title)
    #expect(rows[1].title.contains("Music") && !rows[1].title.contains("com.apple"))
    #expect(!PermissionsRows.isWaiting(entries, app: known))

    let waiting: (String) -> AppIdentity = { AppIdentity(bundleID: $0) }
    #expect(PermissionsRows.shown(entries, app: waiting).map(\.entry.id) == ["calendar"])
    #expect(PermissionsRows.isWaiting(entries, app: waiting))
}

/// A player in a protected folder is named after its file ("Spotify", never "client" or the identifier).
@Test func aProtectedPlayerIsNamedAfterItsFile() {
    let entries = PermissionEntry.entries([PermissionUse(kind: .automation(bundleID: "com.spotify.client"), module: .media, reason: "M")])
    let spotify = AppIdentity(bundleID: "com.spotify.client", presence: .installed,
                              name: AppIdentity.name(of: URL(fileURLWithPath: "/Users/me/Downloads/Spotify.app")),
                              url: URL(fileURLWithPath: "/Users/me/Downloads/Spotify.app"))
    let rows = PermissionsRows.shown(entries) { _ in spotify }
    #expect(rows.count == 1 && rows[0].title.contains("Spotify") && !rows[0].title.contains("client"))
}

/// Search offers exactly the Automation rows the pane shows, once the lookups landed.
@MainActor @Test func searchOffersOnlyInstalledAutomationApps() async {
    let registry = ModuleRegistry(services: .preview())
    registry.declare(.automation(bundleID: "com.apple.Music"), reason: "M")
    registry.declare(.automation(bundleID: "com.spotify.client"), reason: "S")
    let identities = AppIdentityResolver(locate: { id in
        id == "com.apple.Music" ? AppIdentity.Location(url: URL(fileURLWithPath: "/System/Applications/Music.app"),
                                                       name: "Music", isSafeToRead: true) : nil
    }, icon: { _ in nil })
    #expect(PermissionsRows.all(registry: registry, identities: identities).isEmpty)          // both still pending
    for _ in 0..<3000 where identities.revision < 2 { try? await Task.sleep(for: .milliseconds(10)) }
    let rows = PermissionsRows.all(registry: registry, identities: identities)
    #expect(rows.map(\.id) == ["permissions.automation.com.apple.Music"])
    #expect(rows.allSatisfy { !$0.title.contains("com.") })
}
