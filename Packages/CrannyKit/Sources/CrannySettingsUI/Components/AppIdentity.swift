// CrannySettingsUI/Components/AppIdentity.swift — the name and icon of an app given its bundle identifier, for the
// Excluded apps list and the Automation rows of Permissions. Apps in protected folders (`ProtectedLocations`, e.g. an
// app left in Downloads) show their identifier and a generic icon, so Settings never raises a Files & Folders prompt.
// The Launch Services lookup and the bundle's display name are read off the main actor, once per app and session
// (ARCHITECTURE §9.2); views show the identifier until the name arrives.
import AppKit
import Foundation
import Observation
import SwiftUI

struct AppIdentity {
    let bundleID: String
    let name: String
    let icon: NSImage?

    /// Where the app is and its display name, or nil when it is unknown or in a protected folder. Off the main actor.
    @concurrent static func locate(_ bundleID: String) async -> (url: URL, name: String)? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID),
              ProtectedLocations.isSafeToRead(url) else { return nil }
        let name = FileManager.default.displayName(atPath: url.path)
        return (url, name.hasSuffix(".app") ? String(name.dropLast(4)) : name)
    }
}

/// Resolved app identities for the session, shared by every view that lists apps.
@MainActor @Observable final class AppIdentities {
    static let shared = AppIdentities()

    private var resolved: [String: AppIdentity] = [:]
    @ObservationIgnored private var pending: Set<String> = []

    /// How many apps have been resolved (part of the search index's signature: names replace identifiers).
    var resolvedCount: Int { resolved.count }

    /// The app's name and icon. The first call per app starts the lookup and returns the identifier with a generic
    /// icon; views reading this update when the lookup finishes.
    func identity(of bundleID: String) -> AppIdentity {
        if let known = resolved[bundleID] { return known }
        if pending.insert(bundleID).inserted {
            Task { [weak self] in
                let location = await AppIdentity.locate(bundleID)
                // Icon Services renders the icon lazily, when it is drawn.
                let icon = location.map { NSWorkspace.shared.icon(forFile: $0.url.path) }
                self?.resolved[bundleID] = AppIdentity(bundleID: bundleID, name: location?.name ?? bundleID, icon: icon)
                self?.pending.remove(bundleID)
            }
        }
        return AppIdentity(bundleID: bundleID, name: bundleID, icon: nil)
    }
}

/// A 20-pt app icon, or a generic placeholder.
struct AppIconView: View {
    let icon: NSImage?
    var body: some View {
        Group {
            if let icon {
                Image(nsImage: icon).resizable().interpolation(.high)
            } else {
                Image(systemName: "app.dashed").resizable().foregroundStyle(.secondary).padding(2)
            }
        }
        .frame(width: 20, height: 20)
        .accessibilityHidden(true)
    }
}

#Preview("App identity") {
    let finder = AppIdentities.shared.identity(of: "com.apple.finder")
    HStack {
        AppIconView(icon: finder.icon)
        Text(verbatim: finder.name)
    }
    .padding()
}
