// CrannySettingsUI/Panes/PermissionsPane.swift — Settings ▸ Permissions (DESIGN.md §11.1, ARCHITECTURE §3.12, §7.13): one row
// per permission a module declared (`registry.permissionUses`), with a status pill (Granted / Not yet / Denied), the
// one-line why, and Grant… or Open System Settings. Statuses are read with `PermissionsCenter` (never prompts) when the
// pane appears and whenever the app becomes active; a system prompt appears only after a click on Grant….
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

    static func title(_ kind: PermissionKind) -> String {
        if case .automation(let bundleID) = kind {
            return String(localized: "Automation: \(AppIdentity.resolve(bundleID).name)", bundle: .module,
                          comment: "Settings ▸ Permissions: Apple Events permission for one app; the argument is the app's name")
        }
        return kind.title
    }

    static func all(registry: ModuleRegistry) -> [SettingsRowInfo] {
        PermissionEntry.entries(registry.permissionUses).map { SettingsRowInfo(.permissions, $0.id, title: title($0.kind)) }
    }
}

struct PermissionsPane: View {
    let registry: ModuleRegistry

    var body: some View {
        let entries = PermissionEntry.entries(registry.permissionUses)
        SettingsForm(.permissions) {
            Section {
                if entries.isEmpty {
                    Label {
                        Text("No feature has asked for a permission.", bundle: .module, comment: "Settings ▸ Permissions: no module declared a permission")
                    } icon: {
                        Image(systemName: "hand.raised.fill").foregroundStyle(.secondary)
                    }
                    .foregroundStyle(.secondary)
                }
                ForEach(entries) { entry in
                    PermissionRow(entry: entry, permissions: registry.services.permissions)
                }
            } footer: {
                Text("Cranny asks for a permission only when you turn on a feature that needs it, and works without any of them.",
                     bundle: .module, comment: "Settings ▸ Permissions: footer")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .onAppear { registry.services.permissions.refresh() }
        .onReceiveAppActivation { registry.services.permissions.refresh() }
    }
}

private struct PermissionRow: View {
    let entry: PermissionEntry
    let permissions: PermissionsCenter
    @State private var isRequesting = false

    var body: some View {
        let status = permissions.status(entry.kind)
        LabeledContent {
            HStack(spacing: 10) {
                StatusPill(status: status)
                if isRequesting {
                    ProgressView().controlSize(.small)
                } else if let action = PermissionAction(kind: entry.kind, status: status) {
                    Button {
                        perform(action)
                    } label: {
                        Text(verbatim: action.title)
                    }
                }
            }
        } label: {
            RowLabel(title: PermissionsRows.title(entry.kind), footnote: entry.reasons.joined(separator: " "))
        }
        .searchTarget(SettingsRowInfo(.permissions, entry.id, title: PermissionsRows.title(entry.kind)))
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

/// Granted (green) / Not yet / Denied (red): the text carries the meaning, the colour repeats it.
private struct StatusPill: View {
    let status: PermissionStatus

    var body: some View {
        Text(verbatim: title)
            .font(.caption.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(color.opacity(0.14), in: Capsule(style: .continuous))
            .accessibilityLabel(Text("Status: \(title)", bundle: .module,
                                     comment: "Settings ▸ Permissions: VoiceOver label of the status pill; the argument is the status"))
    }

    private var title: String {
        switch status {
        case .granted: String(localized: "Granted", bundle: .module, comment: "Settings ▸ Permissions: status pill")
        case .notDetermined: String(localized: "Not yet", bundle: .module, comment: "Settings ▸ Permissions: status pill (never asked)")
        case .denied: String(localized: "Denied", bundle: .module, comment: "Settings ▸ Permissions: status pill")
        case .restricted: String(localized: "Restricted", bundle: .module, comment: "Settings ▸ Permissions: status pill (blocked by a profile)")
        case .unknown: String(localized: "Unknown", bundle: .module, comment: "Settings ▸ Permissions: status pill (macOS cannot tell yet)")
        }
    }

    private var color: Color {
        switch status {
        case .granted: .green
        case .denied, .restricted: .red
        case .notDetermined, .unknown: .secondary
        }
    }
}

#Preview("Permissions") {
    let registry = ModuleRegistry(services: .preview())
    registry.declare(.calendar, reason: "Show your events in Cranny. Cranny never edits or uploads them.")
    registry.declare(.accessibility, reason: "Replace the system volume and brightness overlay.")
    return PermissionsPane(registry: registry).frame(width: 650, height: 400)
}
