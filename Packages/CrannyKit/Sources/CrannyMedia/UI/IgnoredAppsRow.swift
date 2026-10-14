// CrannyMedia/UI/IgnoredAppsRow.swift — Settings ▸ Media ▸ Ignore apps: players whose sessions never show. Add from
// the players seen this session or pick any app; remove with −. The only "source" control (no priority list).
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
        SettingRow(isDefault: ignored.isEmpty, reset: { settings.reset(MediaSettings.ignoredBundleIDs) }) {
            LabeledContent {
                Menu {
                    ForEach(candidates, id: \.self) { bundleID in
                        Button { add(bundleID) } label: { Text(verbatim: PlayerApps.name(for: bundleID)) }
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
            HStack(spacing: Space.s) {
                if let icon = PlayerApps.icon(for: bundleID) {
                    Image(nsImage: icon).resizable().frame(width: 16, height: 16).accessibilityHidden(true)
                }
                Text(verbatim: PlayerApps.name(for: bundleID))
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
