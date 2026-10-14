// CrannyHUD/UI/HUDSettingsRows.swift — the Settings conventions of DESIGN.md §11.3 for this module pane (an
// opaque view to CrannySettingsUI): Core's row conventions (dot, "Reset to Default") and permission status pill,
// and one-line footnotes in `.secondary`.
// Settings is an ordinary window: system colours and text styles, not the notch tokens.
import CrannyCore
import SwiftUI

/// A label with an optional one-line footnote under it (System Settings style).
struct FootnotedLabel: View {
    let title: Text
    var footnote: Text?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            title
            if let footnote {
                footnote.font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

extension View {
    /// Core's row conventions for `key` (the changed dot, "Reset to Default", the VoiceOver hint).
    func resettable<Value: Codable & Sendable & Equatable>(_ key: SettingKey<Value>, in settings: SettingsStore) -> some View {
        crannySettingRow(settings, key)
    }
}

// The permission status pill is Core's `PermissionStatusPill` (one status mapping for every pane).

#Preview("Rows") {
    let settings = CrannyServices.preview().settings
    settings[HUDSettings.showsValue] = true
    return Form {
        Toggle(isOn: settings.binding(HUDSettings.showsValue)) {
            FootnotedLabel(title: Text(verbatim: "Show value"), footnote: Text(verbatim: "A one-line footnote."))
        }
        .resettable(HUDSettings.showsValue, in: settings)
        LabeledContent {
            HStack { PermissionStatusPill(status: .granted); PermissionStatusPill(status: .notDetermined); PermissionStatusPill(status: .denied) }
        } label: {
            Text(verbatim: "Accessibility")
        }
    }
    .formStyle(.grouped)
    .frame(width: 560, height: 220)
}
