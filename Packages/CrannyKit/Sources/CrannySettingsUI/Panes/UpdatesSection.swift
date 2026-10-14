// CrannySettingsUI/Panes/UpdatesSection.swift — General's Launch at login row and Updates section (DESIGN.md §11.1),
// both driven through `AppControl` (the login item is not a setting: `SMAppService` is the source of truth, D15;
// the update check is GitHub Releases, never a download).
import AppKit
import CrannyCore
import Foundation
import SwiftUI

/// Launch at login: `SMAppService.mainApp` through `AppControl`, with the approval and failure states.
struct LoginItemRow: View {
    let app: any AppControl

    var body: some View {
        let state = app.loginItem
        Toggle(isOn: Binding(get: { state == .enabled || state == .requiresApproval },
                             set: { app.setLaunchAtLogin($0) })) {
            RowLabel(title: GeneralRows.launchAtLogin.title, footnote: footnote(state))
        }
        .toggleStyle(.switch)
        .controlSize(.small)
        .disabled(isUnavailable(state))
        .settingRow(GeneralRows.launchAtLogin, isDefault: true, reset: {})
        if state == .requiresApproval {
            Button {
                if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                Text("Open Login Items…", bundle: .module, comment: "Settings ▸ General: opens System Settings ▸ Login Items")
            }
        }
    }

    private func isUnavailable(_ state: LoginItemState) -> Bool {
        if case .unavailable = state { return true }
        return false
    }

    private func footnote(_ state: LoginItemState) -> String? {
        switch state {
        case .requiresApproval:
            String(localized: "Allow Cranny in System Settings ▸ Login Items to finish.", bundle: .module,
                   comment: "Settings ▸ General: footnote while the login item waits for approval")
        case .unavailable(let reason): reason
        case .enabled, .disabled: nil
        }
    }
}

/// Check daily via GitHub Releases, Check Now, include pre-releases (DESIGN.md §11.1, ARCHITECTURE §7.11).
struct UpdatesSection: View {
    let settings: SettingsStore
    let app: any AppControl

    var body: some View {
        Section {
            ToggleRow(info: GeneralRows.checkForUpdates, settings: settings, key: CoreSettings.checksForUpdates,
                      footnote: String(localized: "Asks GitHub for new releases once a day. Nothing is downloaded or installed.",
                                       bundle: .module, comment: "Settings ▸ General: footnote of Check for updates daily"))
            ToggleRow(info: GeneralRows.prereleases, settings: settings, key: CoreSettings.includesPrereleases)
            UpdateStatusRow(app: app, lastCheck: settings[CoreSettings.lastUpdateCheck])
        } header: {
            Text("Updates", bundle: .module, comment: "Settings: section header (General, About)")
        }
    }
}

/// The result of the last check and the Check Now button. Shared with About.
struct UpdateStatusRow: View {
    let app: any AppControl
    let lastCheck: Date?

    var body: some View {
        LabeledContent {
            Button {
                app.checkForUpdates()
            } label: {
                Text("Check Now", bundle: .module, comment: "Settings: button that checks for updates")
            }
            .disabled(app.update == .checking)
        } label: {
            HStack(spacing: 6) {
                if app.update == .checking { ProgressView().controlSize(.small) }
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: status)
                    if case .available(_, let notes) = app.update {
                        Link(destination: notes) {
                            Text("Release notes", bundle: .module, comment: "Settings: link to the notes of an available update")
                        }
                        .font(.footnote)
                    }
                }
            }
        }
    }

    private var status: String {
        switch app.update {
        case .checking:
            String(localized: "Checking…", bundle: .module, comment: "Settings: update check in progress")
        case .upToDate:
            String(localized: "Cranny is up to date.", bundle: .module, comment: "Settings: result of an update check")
        case .available(let version, _):
            String(localized: "Version \(version) is available.", bundle: .module,
                   comment: "Settings: result of an update check; the argument is a version number")
        case .failed(let reason):
            reason
        case .idle:
            lastCheck.map { date in
                String(localized: "Last checked \(date.formatted(.relative(presentation: .named)))", bundle: .module,
                       comment: "Settings: time of the last update check; the argument is a relative date (\"yesterday\")")
            } ?? String(localized: "Not checked yet", bundle: .module, comment: "Settings: no update check has run")
        }
    }
}

#Preview("Updates") {
    let services = CrannyServices.preview()
    Form {
        LoginItemRow(app: services.app)
        UpdatesSection(settings: services.settings, app: services.app)
    }
    .formStyle(.grouped)
    .frame(width: 600, height: 320)
}
