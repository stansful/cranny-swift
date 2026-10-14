// CrannyOnboarding/Steps/PermissionsStep.swift — step 5 (DESIGN.md §12.1): rows only for the features of the
// chosen layout, all off. Each says why (the module's own reason, which also says what Cranny does not do).
// "Allow" shows the system prompt then and there; nothing is asked on its own, and "later" is fine.
import CrannyCore
import Foundation
import SwiftUI

struct PermissionsStep: View {
    let flow: WelcomeFlow

    var body: some View {
        let rows = flow.permissionRows
        VStack(alignment: .leading, spacing: Space.l) {
            StepHeader(title: String(localized: "Permissions, only for what you chose", bundle: .module, comment: "Welcome step 5: headline"),
                       message: String(localized: "Everything here is optional. You can allow it later in Settings ▸ Permissions.",
                                       bundle: .module, comment: "Welcome step 5: sentence under the headline"))
            if rows.isEmpty {
                Label {
                    Text("This layout needs no permissions.", bundle: .module, comment: "Welcome step 5: shown when the chosen layout needs no permission")
                } icon: {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                }
                .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(spacing: Space.s) {
                        ForEach(rows) { row in PermissionRowView(row: row, flow: flow) }
                    }
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        }
    }
}

private struct PermissionRowView: View {
    let row: PermissionRow
    let flow: WelcomeFlow
    @State private var isAsking = false

    var body: some View {
        let state = flow.state(of: row)
        HStack(spacing: Space.m) {
            Image(systemName: row.group.symbol)
                .font(.system(size: Space.l, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: Space.xxxl, height: Space.xxxl)
                .background(RoundedRectangle(cornerRadius: Radius.control, style: .continuous).fill(row.group.tint.color))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Space.xxs) {
                Text(verbatim: row.group.title).font(.headline)
                Text(verbatim: row.reasons.first ?? row.group.fallbackReason)
                    .font(.caption).foregroundStyle(.secondary)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Space.m)
            action(state)
        }
        .padding(.horizontal, Space.l)
        .padding(.vertical, Space.m)
        .background(RoundedRectangle(cornerRadius: WelcomeMetrics.cardRadius, style: .continuous).fill(.quaternary.opacity(0.4)))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private func action(_ state: PermissionRowState) -> some View {
        switch state {
        case .askable:
            Button {
                isAsking = true
                Task { await flow.allow(row); isAsking = false }
            } label: {
                Text("Allow", bundle: .module, comment: "Welcome step 5: button that shows the system permission prompt")
            }
            .disabled(isAsking)
        case .granted:
            Label {
                Text("Allowed", bundle: .module, comment: "Welcome step 5: status of a granted permission")
            } icon: {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            }
            .font(.callout)
        case .denied:
            Button { flow.openSystemSettings(row) } label: {
                Text("System Settings…", bundle: .module, comment: "Welcome step 5: opens System Settings for a permission that was turned off")
            }
        case .restricted:
            Text("Managed by your organisation", bundle: .module, comment: "Welcome step 5: status of a permission a device profile controls")
                .font(.callout).foregroundStyle(.secondary)
        case .deferred:
            Text("Asks when needed", bundle: .module, comment: "Welcome step 5: status when the system could not ask yet (e.g. the music app is not running)")
                .font(.callout).foregroundStyle(.secondary)
        }
    }
}

extension PermissionGroup {
    var title: String {
        switch self {
        case .calendar: String(localized: "Calendars", bundle: .module, comment: "Welcome step 5: permission name (System Settings ▸ Privacy)")
        case .accessibility: String(localized: "Accessibility", bundle: .module, comment: "Welcome step 5: permission name (System Settings ▸ Privacy)")
        case .automation: String(localized: "Automation", bundle: .module, comment: "Welcome step 5: permission name (System Settings ▸ Privacy; Apple Events to music apps)")
        case .bluetooth: String(localized: "Bluetooth", bundle: .module, comment: "Welcome step 5: permission name (System Settings ▸ Privacy)")
        }
    }

    /// Used only if a module declared the kind without a reason.
    var fallbackReason: String {
        switch self {
        case .calendar: String(localized: "Show your events in Cranny.", bundle: .module, comment: "Welcome step 5: fallback reason for the Calendars permission")
        case .accessibility: String(localized: "Show volume and brightness in the notch instead of the system HUD.", bundle: .module, comment: "Welcome step 5: fallback reason for the Accessibility permission")
        case .automation: String(localized: "Control Music and Spotify when other ways fail.", bundle: .module, comment: "Welcome step 5: fallback reason for the Automation permission")
        case .bluetooth: String(localized: "Show the battery of every Bluetooth device.", bundle: .module, comment: "Welcome step 5: fallback reason for the Bluetooth permission")
        }
    }

    /// The icon colour, as in System Settings' sidebar (DESIGN.md §11.1).
    var tint: SettingsIconTint {
        switch self {
        case .calendar: .red
        case .accessibility: .blue
        case .automation: .pink
        case .bluetooth: .blue
        }
    }
}

#Preview("Step 5 · Permissions") {
    WelcomePreview(step: .permissions)
}
