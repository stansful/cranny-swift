// CrannySettingsUI/Components/AppIdentity.swift — the icon view of an app row (the Excluded apps list). Names and icons
// come from CrannyCore's `AppIdentityResolver` (also for Permissions' Automation rows): looked up off the main actor,
// named by Finder (the file name for an app in a protected folder, never the bundle identifier), no icon read from a
// protected folder (no Files & Folders prompt from Settings), and an explicit not-installed state.
import AppKit
import CrannyCore
import Foundation
import SwiftUI

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
    let finder = AppIdentityResolver.shared.identity(of: "com.apple.finder")
    HStack {
        AppIconView(icon: finder.icon)
        Text(verbatim: finder.name ?? "")
    }
    .padding()
}
