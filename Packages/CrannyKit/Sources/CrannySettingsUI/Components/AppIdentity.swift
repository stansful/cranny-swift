// CrannySettingsUI/Components/AppIdentity.swift — the name and icon of an app given its bundle identifier, for the
// Excluded apps list and the Automation rows of Permissions. Apps in protected folders (`ProtectedLocations`, e.g. an
// app left in Downloads) show their identifier and a generic icon, so Settings never raises a Files & Folders prompt.
import AppKit
import Foundation
import SwiftUI

struct AppIdentity {
    let bundleID: String
    let name: String
    let icon: NSImage?

    @MainActor static func resolve(_ bundleID: String) -> AppIdentity {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID),
              ProtectedLocations.isSafeToRead(url) else {
            return AppIdentity(bundleID: bundleID, name: bundleID, icon: nil)
        }
        let name = FileManager.default.displayName(atPath: url.path)
        let trimmed = name.hasSuffix(".app") ? String(name.dropLast(4)) : name
        return AppIdentity(bundleID: bundleID, name: trimmed, icon: NSWorkspace.shared.icon(forFile: url.path))
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
    let finder = AppIdentity.resolve("com.apple.finder")
    HStack {
        AppIconView(icon: finder.icon)
        Text(verbatim: finder.name)
    }
    .padding()
}
