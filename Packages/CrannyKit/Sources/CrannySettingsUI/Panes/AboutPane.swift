// CrannySettingsUI/Panes/AboutPane.swift — Settings ▸ About (DESIGN.md §11.1): the app icon as the system renders it
// (`NSApp.applicationIconImage`, so Tinted and Clear appearances apply), version, Check for Updates and release notes,
// GitHub and the MIT licence (when `CrannyGitHubRepository` is set in Info.plist), acknowledgements
// (THIRD_PARTY_NOTICES.md), Replay Tutorial and Show Welcome.
import AppKit
import CrannyCore
import Foundation
import SwiftUI

enum AboutRows {
    static var updates: SettingsRowInfo {
        SettingsRowInfo(.about, "updates",
                        title: String(localized: "Check for Updates", bundle: .module, comment: "Settings ▸ About: row and button"),
                        keywords: [String(localized: "version", bundle: .module, comment: "Settings search: keyword for updates")])
    }
    static var tutorial: SettingsRowInfo {
        SettingsRowInfo(.about, "tutorial",
                        title: String(localized: "Replay Tutorial", bundle: .module, comment: "Settings ▸ About: button that starts the interactive tutorial"))
    }
    static var welcome: SettingsRowInfo {
        SettingsRowInfo(.about, "welcome",
                        title: String(localized: "Show Welcome", bundle: .module, comment: "Settings ▸ About: button that opens the welcome window"),
                        keywords: [String(localized: "onboarding", bundle: .module, comment: "Settings search: keyword for Show Welcome")])
    }
    static var acknowledgements: SettingsRowInfo {
        SettingsRowInfo(.about, "acknowledgements",
                        title: String(localized: "Acknowledgments", bundle: .module, comment: "Settings ▸ About: section header"),
                        keywords: [String(localized: "license", bundle: .module, comment: "Settings search: keyword for the licence and acknowledgements")])
    }

    static var all: [SettingsRowInfo] { [updates, tutorial, welcome, acknowledgements] }

    /// "owner/repo" from Info.plist (`CrannyGitHubRepository`); empty or missing = no links and no update check.
    static var repository: URL? {
        guard let slug = Bundle.main.object(forInfoDictionaryKey: "CrannyGitHubRepository") as? String,
              !slug.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return URL(string: "https://github.com/\(slug)")
    }
}

struct AboutPane: View {
    let registry: ModuleRegistry

    var body: some View {
        let app = registry.services.app
        SettingsForm(.about) {
            Section {
                AboutHeader()
            }
            Section {
                UpdateStatusRow(app: app, lastCheck: registry.services.settings[CoreSettings.lastUpdateCheck])
                    .searchTarget(AboutRows.updates)
                if let repository = AboutRows.repository {
                    LabeledContent {
                        HStack(spacing: 14) {
                            Link(destination: repository) {
                                Text("GitHub", bundle: .module, comment: "Settings ▸ About: link to the source code")
                            }
                            Link(destination: repository.appending(path: "blob/main/LICENSE")) {
                                Text("MIT License", bundle: .module, comment: "Settings ▸ About: link to the licence")
                            }
                        }
                    } label: {
                        Text("Source code", bundle: .module, comment: "Settings ▸ About: row label")
                    }
                }
            } header: {
                Text("Updates", bundle: .module, comment: "Settings: section header (General, About)")
            }
            Section {
                LabeledContent {
                    HStack(spacing: 8) {
                        Button { app.startTutorial() } label: { Text(verbatim: AboutRows.tutorial.title) }
                        Button { app.showWelcome() } label: { Text(verbatim: AboutRows.welcome.title) }
                    }
                } label: {
                    RowLabel(title: String(localized: "Getting started", bundle: .module, comment: "Settings ▸ About: row label"),
                             footnote: String(localized: "The tutorial runs on the real notch and takes about a minute.", bundle: .module,
                                              comment: "Settings ▸ About: footnote of Getting started"))
                }
                .searchTarget(AboutRows.tutorial)
            }
            Acknowledgements()
        }
    }
}

/// Icon, name, version and the licence line.
private struct AboutHeader: View {
    var body: some View {
        let info = AppInfo.current()
        VStack(spacing: 6) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 112, height: 112)
                .accessibilityHidden(true)
            Text(verbatim: "Cranny").font(.title.weight(.semibold))
            Text("Version \(info.version) (\(info.build))", bundle: .module, comment: "Settings ▸ About: marketing version and build")
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            Text("Free and open source under the MIT License.", bundle: .module, comment: "Settings ▸ About: licence line")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }
}

/// THIRD_PARTY_NOTICES.md: projects studied for techniques; no code, assets or text were copied.
private struct Acknowledgements: View {
    private struct Entry: Identifiable {
        let name: String
        let license: String
        let url: URL?
        let note: String
        var id: String { name }
    }

    private var entries: [Entry] {
        [
            Entry(name: "mediaremote-adapter", license: "BSD-3-Clause", url: URL(string: "https://github.com/ungive/mediaremote-adapter"),
                  note: String(localized: "Showed that Now Playing can still be read from a helper hosted in the system’s Perl.", bundle: .module,
                               comment: "Settings ▸ About ▸ Acknowledgements: what Cranny learned from mediaremote-adapter")),
            Entry(name: "volumeHUD", license: "MIT", url: URL(string: "https://github.com/dannystewart/volumeHUD"),
                  note: String(localized: "Showed how to replace the system volume overlay so only one is ever shown.", bundle: .module,
                               comment: "Settings ▸ About ▸ Acknowledgements: what Cranny learned from volumeHUD")),
        ]
    }

    var body: some View {
        Section {
            ForEach(entries) { entry in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        if let url = entry.url {
                            Link(destination: url) { Text(verbatim: entry.name) }
                        } else {
                            Text(verbatim: entry.name)
                        }
                        Text(verbatim: entry.license).font(.caption).foregroundStyle(.secondary)
                    }
                    Text(verbatim: entry.note).font(.footnote).foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }
        } header: {
            Text(verbatim: AboutRows.acknowledgements.title)
        } footer: {
            Text("Studied for techniques only. Cranny includes no third-party code.", bundle: .module,
                 comment: "Settings ▸ About ▸ Acknowledgements: footer")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .searchTarget(AboutRows.acknowledgements)
    }
}

#Preview("About") {
    AboutPane(registry: ModuleRegistry(services: .preview()))
        .frame(width: 650, height: 620)
}
