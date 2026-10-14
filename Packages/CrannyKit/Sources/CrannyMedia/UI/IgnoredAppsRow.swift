// CrannyMedia/UI/IgnoredAppsRow.swift — Settings ▸ Media ▸ Ignore apps: players whose sessions never show. Add from
// the players seen this session or pick any app; remove with −. The only "source" control (no priority list). Apps are
// named by CrannyCore's `AppIdentityResolver` (Finder's name, never the bundle identifier); an ignored app that is no
// longer installed reads "App not installed", and a player whose name is not known yet is not offered.
import AppKit
import CrannyCore
import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct IgnoredAppsRow: View {
    let service: MediaService
    let settings: SettingsStore

    var body: some View {
        let ignored = settings[MediaSettings.ignoredBundleIDs]
        let candidates = service.recentSources.filter { !ignored.contains($0) }
            .compactMap { id in PlayerApps.name(for: id).map { (bundleID: id, name: $0) } }
        SettingRow(isDefault: ignored.isEmpty, reset: { settings.reset(MediaSettings.ignoredBundleIDs) }) {
            LabeledContent {
                Menu {
                    ForEach(candidates, id: \.bundleID) { candidate in
                        Button { add(candidate.bundleID) } label: { Text(verbatim: candidate.name) }
                    }
                    if !candidates.isEmpty { Divider() }
                    Button { chooseApp() } label: { Text(verbatim: MediaPaneStrings.chooseApp) }
                } label: {
                    Text(verbatim: MediaPaneStrings.add)
                }
                .fixedSize()
            } label: {
                Text(verbatim: MediaPaneStrings.ignoreApps)
            }
        }
        ForEach(ignored, id: \.self) { bundleID in
            let identity = PlayerApps.identity(bundleID)
            HStack(spacing: Space.s) {
                if let icon = identity.icon {
                    Image(nsImage: icon).resizable().frame(width: 16, height: 16).accessibilityHidden(true)
                }
                if let name = identity.name {
                    Text(verbatim: name)
                } else if identity.isNotInstalled {
                    Text(verbatim: MediaPaneStrings.appNotInstalled).foregroundStyle(.secondary)
                }
                Spacer()
                Button { remove(bundleID) } label: { Image(systemName: "xmark") }
                    .buttonStyle(.borderless)
                    .help(MediaPaneStrings.stopIgnoring)
                    .accessibilityLabel(Text(verbatim: MediaPaneStrings.stopIgnoring))
            }
            .padding(.leading, Space.l)
        }
    }

    private func add(_ bundleID: String) {
        var ids = settings[MediaSettings.ignoredBundleIDs]
        guard !ids.contains(bundleID) else { return }
        ids.append(bundleID)
        settings[MediaSettings.ignoredBundleIDs] = ids
    }

    private func remove(_ bundleID: String) {
        settings[MediaSettings.ignoredBundleIDs] = settings[MediaSettings.ignoredBundleIDs].filter { $0 != bundleID }
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = MediaPaneStrings.ignoreApps
        guard panel.runModal() == .OK, let url = panel.url, let bundleID = Bundle(url: url)?.bundleIdentifier else { return }
        add(bundleID)
    }
}

#Preview("Ignore apps") {
    let services = CrannyServices.preview()
    services.settings[MediaSettings.ignoredBundleIDs] = ["com.apple.Safari"]
    let service = SampleMedia.service(settings: services.settings, environment: services.environment, permissions: services.permissions)
    return Form { Section { IgnoredAppsRow(service: service, settings: services.settings) } }
        .formStyle(.grouped)
        .frame(width: 520, height: 200)
}
