// CrannySettingsUI/Panes/PermissionsPane.swift — Settings ▸ Permissions (DESIGN.md §11.1, ARCHITECTURE §3.12, §7.13): one row
// per permission a module declared (`registry.permissionUses`), with a status pill (Granted / Not yet / Denied), the
// one-line why, and Grant… or Open System Settings. Statuses are read with `PermissionsCenter` (never prompts, off the
// main actor) when the pane appears; the center refreshes them itself whenever the app becomes active (the rows follow
// `statuses`), so an activation only looks the apps up again. A system prompt appears only after a click on Grant…. An Automation row is
// named after its app (CrannyCore's `AppIdentityResolver`: Finder's name, never the bundle identifier) and shown
// only while that app is installed. Automation statuses come from `PermissionsCenter`'s cache, read off the main actor:
// a row shows a small spinner until its first answer lands, and no view body runs an Apple Events query.
import AppKit
import CrannyCore
import Foundation
import SwiftUI

/// One permission row: its kind and every reason a module gave for it.
struct PermissionEntry: Identifiable, Equatable {
    let kind: PermissionKind
    let reasons: [String]
    var id: String { PermissionsRows.key(kind) }

    /// The declared uses, one entry per kind, in the design's order (Calendar, Camera, Accessibility, Automation,
    /// Bluetooth, System Audio Recording); reasons are kept once each, in declaration order.
    static func entries(_ uses: [PermissionUse]) -> [PermissionEntry] {
        var order: [PermissionKind] = []
        var reasons: [PermissionKind: [String]] = [:]
        for use in uses {
            if reasons[use.kind] == nil { order.append(use.kind); reasons[use.kind] = [] }
            if reasons[use.kind]?.contains(use.reason) == false { reasons[use.kind]?.append(use.reason) }
        }
        return order.enumerated()
            .sorted { (rank($0.element), $0.offset) < (rank($1.element), $1.offset) }
            .map { PermissionEntry(kind: $0.element, reasons: reasons[$0.element] ?? []) }
    }

    private static func rank(_ kind: PermissionKind) -> Int {
        switch kind {
        case .calendar: 0
        case .camera: 1
        case .accessibility: 2
        case .automation: 3
        case .bluetooth: 4
        case .systemAudioRecording: 5
        }
    }
}

enum PermissionsRows {
    static func key(_ kind: PermissionKind) -> String {
        switch kind {
        case .accessibility: "accessibility"
        case .calendar: "calendar"
        case .camera: "camera"
        case .bluetooth: "bluetooth"
        case .systemAudioRecording: "systemAudioRecording"
        case .automation(let bundleID): "automation.\(bundleID)"
        }
    }

    /// The row's title, or nil while the row is not shown: an Automation row is named after its app ("Automation:
    /// Music") once the app is known to be installed, and never after its bundle identifier (§10.20 issue 11).
    static func title(_ kind: PermissionKind, app: (String) -> AppIdentity) -> String? {
        guard case .automation(let bundleID) = kind else { return kind.title }
        let identity = app(bundleID)
        guard identity.isInstalled else { return nil }
        return identity.name.map {
            String(localized: "Automation: \($0)", bundle: .module,
                   comment: "Settings ▸ Permissions: Apple Events permission for one app; the argument is the app's name (Music, Spotify)")
        }
    }

    /// The rows the pane shows, with their titles, in the design's order.
    static func shown(_ entries: [PermissionEntry], app: (String) -> AppIdentity) -> [(entry: PermissionEntry, title: String)] {
        entries.compactMap { entry in title(entry.kind, app: app).map { (entry, $0) } }
    }

    /// An Automation row still waits for its app's lookup.
    static func isWaiting(_ entries: [PermissionEntry], app: (String) -> AppIdentity) -> Bool {
        entries.contains { entry in
            if case .automation(let bundleID) = entry.kind { return app(bundleID).isPending }
            return false
        }
    }

    /// The search rows: exactly the rows the pane shows.
    static func all(registry: ModuleRegistry, identities: AppIdentityResolver = .shared) -> [SettingsRowInfo] {
        shown(PermissionEntry.entries(registry.permissionUses), app: identities.identity(of:)).map {
            SettingsRowInfo(.permissions, $0.entry.id, title: $0.title)
        }
    }
}

struct PermissionsPane: View {
    let registry: ModuleRegistry
    private var identities: AppIdentityResolver { .shared }

    var body: some View {
        let entries = PermissionEntry.entries(registry.permissionUses)
        let rows = PermissionsRows.shown(entries, app: identities.identity(of:))
        SettingsForm(.permissions) {
            Section {
                if rows.isEmpty && !PermissionsRows.isWaiting(entries, app: identities.identity(of:)) {
                    Label {
                        Text("No feature has asked for a permission.", bundle: .module, comment: "Settings ▸ Permissions: no module declared a permission")
                    } icon: {
                        Image(systemName: "hand.raised.fill").foregroundStyle(.secondary)
                    }
                    .foregroundStyle(.secondary)
                }
                ForEach(rows, id: \.entry.id) { row in
                    PermissionRow(entry: row.entry, title: row.title, permissions: registry.services.permissions)
                }
            } footer: {
                Text("Cranny asks for a permission only when you turn on a feature that needs it, and works without any of them.",
                     bundle: .module, comment: "Settings ▸ Permissions: footer")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .onAppear { refresh() }
        .onReceiveAppActivation { identities.refresh() }      // statuses: the center's own activation refresh
    }

    /// Statuses and Automation apps may have changed while the pane was away (System Settings, an installer).
    private func refresh() {
        registry.services.permissions.refreshInBackground()
        identities.refresh()
    }
}

private struct PermissionRow: View {
    let entry: PermissionEntry
    let title: String
    let permissions: PermissionsCenter
    @State private var isRequesting = false

    var body: some View {
        let status = permissions.knownStatus(entry.kind)
        LabeledContent {
            HStack(spacing: 10) {
                if let status {
                    PermissionStatusPill(status: status)
                }
                if isRequesting || status == nil {
                    ProgressView().controlSize(.small)          // a request, or the first Automation answer, runs
                } else if let status, let action = PermissionAction(kind: entry.kind, status: status) {
                    Button {
                        perform(action)
                    } label: {
                        Text(verbatim: action.title)
                    }
                }
            }
        } label: {
            RowLabel(title: title, footnote: entry.reasons.joined(separator: " "))
        }
        .searchTarget(SettingsRowInfo(.permissions, entry.id, title: title))
        .accessibilityElement(children: .contain)
    }

    private func perform(_ action: PermissionAction) {
        switch action {
        case .openSettings:
            permissions.openSystemSettings(entry.kind)
        case .grant:
            isRequesting = true
            Task {
                _ = await permissions.request(entry.kind)
                isRequesting = false
            }
        }
    }
}

/// The button of a permission row: Grant… while the system can still ask (and has an API to), System Settings
/// otherwise, nothing once granted.
enum PermissionAction: Equatable {
    case grant, openSettings

    init?(kind: PermissionKind, status: PermissionStatus) {
        switch status {
        case .granted: return nil
        case .notDetermined: self = kind == .systemAudioRecording ? .openSettings : .grant
        case .denied, .restricted, .unknown: self = .openSettings
        }
    }

    var title: String {
        switch self {
        case .grant: String(localized: "Grant…", bundle: .module, comment: "Settings ▸ Permissions: button that shows the system prompt")
        case .openSettings: String(localized: "Open System Settings", bundle: .module, comment: "Settings ▸ Permissions: button that opens Privacy & Security")
        }
    }
}

#Preview("Permissions") {
    let registry = ModuleRegistry(services: .preview())
    registry.declare(.calendar, reason: "Show your events in Cranny. Cranny never edits or uploads them.")
    registry.declare(.accessibility, reason: "Replace the system volume and brightness overlay.")
    registry.declare(.automation(bundleID: "com.apple.Music"), reason: "Read and control Music when the media helper can’t.")
    registry.declare(.automation(bundleID: "com.example.not-installed"), reason: "Never shown: the app is not installed.")
    return PermissionsPane(registry: registry).frame(width: 650, height: 400)
}
