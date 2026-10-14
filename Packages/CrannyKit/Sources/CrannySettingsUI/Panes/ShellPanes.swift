// CrannySettingsUI/Panes/ShellPanes.swift — the panes CrannySettingsUI owns itself (DESIGN.md §11.1):
// General, Appearance, Keyboard, Layout & Widgets, Live Activities, Gestures, Permissions, About.
// Module panes (HUD, Media, Calendar, Shortcuts, Tray) come from `registry.settingsPages`.
// WP0: the sidebar entries are final; most detail views are placeholders until WP14.
import AppKit
import CrannyCore
import Foundation
import SwiftUI

enum ShellPanes {
    @MainActor static func all(registry: ModuleRegistry) -> [SettingsPage] {
        let settings = registry.services.settings
        func page(_ id: SettingsPageID, _ title: String, _ symbol: String, _ tint: SettingsIconTint, _ group: SettingsGroup,
                  _ order: Int, namespaces: [ModuleID], preview: PreviewStageState?,
                  view: @escaping @MainActor () -> AnyView) -> SettingsPage {
            SettingsPage(id: id, title: title, symbol: symbol, tint: tint, group: group, order: order,
                         namespaces: namespaces, previewState: preview, makeView: view)
        }
        return [
            page(.general, String(localized: "General", bundle: .module, comment: "Settings sidebar: pane name"), "gearshape.fill", .gray, .top, 0,
                 namespaces: [.general, .displays], preview: .closed) { AnyView(GeneralPane(settings: settings)) },
            page(.appearance, String(localized: "Appearance", bundle: .module, comment: "Settings sidebar: pane name"), "paintbrush.fill", .purple, .top, 1,
                 namespaces: [.appearance], preview: .open) { AnyView(PlaceholderPane()) },
            page(.keyboard, String(localized: "Keyboard", bundle: .module, comment: "Settings sidebar: pane name"), "keyboard", .indigo, .top, 2,
                 namespaces: [.keyboard], preview: .open) { AnyView(PlaceholderPane()) },
            page(.nookAndWidgets, String(localized: "Layout & Widgets", bundle: .module, comment: "Settings sidebar: pane name (code id `nook`)"),
                 "square.grid.2x2.fill", .blue, .notch, 0, namespaces: [.nook], preview: .open) { AnyView(PlaceholderPane()) },
            page(.liveActivities, String(localized: "Live Activities", bundle: .module, comment: "Settings sidebar: pane name"),
                 "capsule.tophalf.filled", .pink, .notch, 1, namespaces: [.activities], preview: .activity) { AnyView(PlaceholderPane()) },
            page(.gestures, String(localized: "Gestures", bundle: .module, comment: "Settings sidebar: pane name"), "hand.draw.fill", .orange, .notch, 3,
                 namespaces: [.gestures], preview: .closed) { AnyView(PlaceholderPane()) },
            page(.permissions, String(localized: "Permissions", bundle: .module, comment: "Settings sidebar: pane name"), "hand.raised.fill", .blue, .bottom, 0,
                 namespaces: [], preview: nil) { AnyView(PlaceholderPane()) },
            page(.about, String(localized: "About", bundle: .module, comment: "Settings sidebar: pane name"), "info.circle.fill", .gray, .bottom, 1,
                 namespaces: [], preview: nil) { AnyView(AboutPane()) },
        ]
    }
}

/// Until WP14 builds the pane.
struct PlaceholderPane: View {
    var body: some View {
        Form {
            Text("Nothing to set here yet.", bundle: .module, comment: "Settings: placeholder pane")
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }
}

struct GeneralPane: View {
    let settings: SettingsStore
    var body: some View {
        Form {
            Toggle(isOn: settings.binding(CoreSettings.closeOnLeave)) {
                Text("Close when the pointer leaves", bundle: .module, comment: "Settings ▸ General: toggle")
            }
            .toggleStyle(.switch)
            .controlSize(.small)
        }
        .formStyle(.grouped)
    }
}

struct AboutPane: View {
    var body: some View {
        let info = AppInfo.current()
        VStack(spacing: 12) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
                .accessibilityHidden(true)
            Text(verbatim: "Cranny").font(.title.weight(.semibold))
            Text("Version \(info.version) (\(info.build))", bundle: .module, comment: "Settings ▸ About: marketing version and build")
                .foregroundStyle(.secondary)
            Text("Free and open source under the MIT License.", bundle: .module, comment: "Settings ▸ About: licence line")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview("General") {
    GeneralPane(settings: ModuleRegistry(services: .preview()).services.settings)
        .frame(width: 600, height: 300)
        .background(.black)
        .preferredColorScheme(.dark)
        .crannyThemeRoot(CrannyTheme())
}

#Preview("About") {
    AboutPane()
        .frame(width: 600, height: 400)
        .background(.black)
        .preferredColorScheme(.dark)
        .crannyThemeRoot(CrannyTheme())
}
