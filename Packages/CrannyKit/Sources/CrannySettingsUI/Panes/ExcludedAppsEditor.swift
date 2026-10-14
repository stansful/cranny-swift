// CrannySettingsUI/Panes/ExcludedAppsEditor.swift — General ▸ Excluded apps (DESIGN.md §3.7): while one of these apps
// is in front, Cranny behaves as it does over full-screen apps. Add from the running apps or with an Open panel in
// /Applications (the panel is the user's own choice, so it raises no prompt); remove with the row's button. Rows name
// their app with CrannyCore's `AppIdentityResolver` and never show a bundle identifier: an app that is no longer
// installed reads "App not installed" (it can still be removed), and a row whose lookup still runs shows no name yet.
import AppKit
import CrannyCore
import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct ExcludedAppsEditor: View {
    let settings: SettingsStore

    var body: some View {
        let ids = settings[CoreSettings.excludedBundleIDs]
        LabeledContent {
            AddAppMenu(excluded: ids) { add($0) }
        } label: {
            RowLabel(title: GeneralRows.excludedApps.title,
                     footnote: ids.isEmpty ? String(localized: "While an excluded app is in front, Cranny acts as it does over full-screen apps.",
                                                    bundle: .module, comment: "Settings ▸ General: footnote of Excluded apps") : nil,
                     isChanged: !ids.isEmpty)
        }
        .settingRow(GeneralRows.excludedApps, settings: settings, key: CoreSettings.excludedBundleIDs)
        .onAppear { AppIdentityResolver.shared.refresh() }      // an app may have been installed or removed meanwhile
        ForEach(ids, id: \.self) { id in
            ExcludedAppRow(identity: AppIdentityResolver.shared.identity(of: id)) {
                settings[CoreSettings.excludedBundleIDs].removeAll { $0 == id }
            }
        }
    }

    private func add(_ bundleIDs: [String]) {
        var ids = settings[CoreSettings.excludedBundleIDs]
        for id in bundleIDs where !ids.contains(id) { ids.append(id) }
        settings[CoreSettings.excludedBundleIDs] = ids
    }
}

/// One excluded app: its icon and Finder's name, and the remove button.
private struct ExcludedAppRow: View {
    let identity: AppIdentity
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            AppIconView(icon: identity.icon)
            if let name = identity.name {
                Text(verbatim: name).lineLimit(1)
            } else if identity.isNotInstalled {
                Text("App not installed", bundle: .module,
                     comment: "Settings ▸ General ▸ Excluded apps: row of an excluded app that is no longer installed")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button(action: remove) {
                Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(removeLabel)
        }
        .padding(.leading, 16)
    }

    private var removeLabel: Text {
        if let name = identity.name {
            return Text("Remove \(name)", bundle: .module,
                        comment: "Settings ▸ General ▸ Excluded apps: remove button (VoiceOver); the argument is an app name")
        }
        return Text("Remove app", bundle: .module,
                    comment: "Settings ▸ General ▸ Excluded apps: remove button (VoiceOver) of an app that is not installed or not looked up yet")
    }
}

/// "+" menu: running apps, then "Choose App…".
private struct AddAppMenu: View {
    let excluded: [String]
    let add: ([String]) -> Void

    var body: some View {
        Menu {
            let running = Self.runningApps(excluding: excluded)
            ForEach(running, id: \.bundleID) { app in
                Button {
                    add([app.bundleID])
                } label: {
                    Text(verbatim: app.name)
                }
            }
            if !running.isEmpty { Divider() }
            Button {
                chooseApps()
            } label: {
                Text("Choose App…", bundle: .module, comment: "Settings ▸ General ▸ Excluded apps: opens a file panel in Applications")
            }
        } label: {
            Text("Add App", bundle: .module, comment: "Settings ▸ General ▸ Excluded apps: menu button")
        }
        .fixedSize()
    }

    /// Regular running apps (not Cranny, not already excluded), sorted by name.
    private static func runningApps(excluding excluded: [String]) -> [(bundleID: String, name: String)] {
        let own = Bundle.main.bundleIdentifier
        return NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app in app.bundleIdentifier.flatMap { id in app.localizedName.map { (id, $0) } } }   // named only
            .filter { $0.0 != own && !excluded.contains($0.0) }
            .sorted { $0.1.localizedStandardCompare($1.1) == .orderedAscending }
            .map { (bundleID: $0.0, name: $0.1) }
    }

    private func chooseApps() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.prompt = String(localized: "Exclude", bundle: .module, comment: "Settings ▸ General ▸ Excluded apps: file panel confirm button")
        panel.begin { response in
            guard response == .OK else { return }
            let ids = panel.urls.compactMap { Bundle(url: $0)?.bundleIdentifier }
            MainActor.assumeIsolated { add(ids) }
        }
    }
}

#Preview("Excluded apps") {
    let settings = CrannyServices.preview().settings
    settings[CoreSettings.excludedBundleIDs] = ["com.apple.finder", "com.example.missing"]
    return Form { ExcludedAppsEditor(settings: settings) }
        .formStyle(.grouped)
        .frame(width: 600, height: 240)
}
