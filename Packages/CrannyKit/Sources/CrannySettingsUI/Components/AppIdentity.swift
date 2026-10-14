// CrannySettingsUI/Components/AppIdentity.swift — the icon view of an app row (the Excluded apps list). Names and icons
// come from CrannyCore's `AppIdentityResolver`: looked up off the main actor, once per app and session, and never for
// an app in a protected folder (no Files & Folders prompt from Settings). Permissions' Automation rows name their app
// with `AutomationApps`, which also knows when an app is not installed.
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
        Text(verbatim: finder.name)
    }
    .padding()
}
