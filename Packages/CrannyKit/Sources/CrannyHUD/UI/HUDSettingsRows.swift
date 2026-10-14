// CrannyHUD/UI/HUDSettingsRows.swift — the Settings conventions of DESIGN.md §11.3 for this module pane (an
// opaque view to CrannySettingsUI): a 6-pt accent dot before a changed row, "Reset to Default" in every row's
// context menu, one-line footnotes in `.secondary`, and the permission status pill of §11.1.
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

/// Marks a row whose key differs from its default and offers "Reset to Default".
struct ResettableRow<Value: Codable & Sendable & Equatable>: ViewModifier {
    let settings: SettingsStore
    let key: SettingKey<Value>

    func body(content: Content) -> some View {
        let changed = !settings.isDefault(key)
        content
            .overlay(alignment: .topLeading) {
                if changed {
                    Circle().fill(.tint)
                        .frame(width: 6, height: 6)
                        .offset(x: -10, y: 5)
                        .accessibilityHidden(true)
                        .help(String(localized: "Changed from the default", bundle: .module,
                                     comment: "Settings ▸ HUD: tooltip of the dot before a changed row"))
                }
            }
            .contextMenu {
                Button {
                    settings.reset(key)
                } label: {
                    Text("Reset to Default", bundle: .module, comment: "Settings ▸ HUD: row context menu item")
                }
                .disabled(!changed)
            }
    }
}

extension View {
    func resettable<Value: Codable & Sendable & Equatable>(_ key: SettingKey<Value>, in settings: SettingsStore) -> some View {
        modifier(ResettableRow(settings: settings, key: key))
    }
}

/// Granted / Not yet / Denied (DESIGN.md §11.1 Permissions): colour plus text, never colour alone.
struct PermissionStatusPill: View {
    let status: PermissionStatus

    var body: some View {
        let (text, color) = presentation
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text).font(.caption.weight(.medium))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .foregroundStyle(color)
        .background(Capsule(style: .continuous).fill(color.opacity(0.14)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(text))
    }

    private var presentation: (String, Color) {
        switch status {
        case .granted:
            (String(localized: "Granted", bundle: .module, comment: "Settings ▸ HUD: Accessibility status pill"), .green)
        case .denied, .restricted:
            (String(localized: "Denied", bundle: .module, comment: "Settings ▸ HUD: Accessibility status pill"), .red)
        case .notDetermined, .unknown:
            (String(localized: "Not yet", bundle: .module, comment: "Settings ▸ HUD: Accessibility status pill (not granted yet)"), .orange)
        }
    }
}

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
