// CrannyCore/Settings/SettingRowConventions.swift
// The conventions every Settings row shares (DESIGN.md §11.3), written once for the shell's panes AND the module panes
// (which cannot import CrannySettingsUI): a 6-pt accent dot before a changed value, "Reset to Default" in the row's
// context menu and as a VoiceOver action, a VoiceOver hint that the value was changed, and one permission status pill
// (§11.1). Settings is an ordinary window: system colours and fonts, not the notch tokens.
import Foundation
import SwiftUI

/// Sizes of the row conventions.
public nonisolated enum SettingRowMetrics {
    /// The changed-value dot.
    public static let changedDot: CGFloat = 6
    /// Gap between the dot and the row's label: the dot sits in the grouped form's leading inset.
    public static let changedDotGap: CGFloat = 4
}

public extension View {
    /// The full row conventions for a row backed by one key: the changed dot, "Reset to Default" (context menu and
    /// VoiceOver action, unavailable at the default) and the VoiceOver hint.
    func crannySettingRow<Value>(_ settings: SettingsStore, _ key: SettingKey<Value>) -> some View {
        crannySettingRow(isDefault: settings.isDefault(key), reset: { settings.reset(key) })
    }

    /// The full row conventions with explicit "is default" and "reset" (rows backed by several keys or a dictionary
    /// entry).
    func crannySettingRow(isDefault: Bool, reset: @escaping @MainActor () -> Void) -> some View {
        crannyChangedDot(!isDefault).crannyResetToDefault(isDefault: isDefault, reset: reset)
    }

    /// The 6-pt accent dot just before the view's first line of text, outside its frame (in the form's leading
    /// inset), while `isChanged`. Decorative: VoiceOver hears the hint of `crannyResetToDefault` instead.
    func crannyChangedDot(_ isChanged: Bool) -> some View {
        overlay(alignment: Alignment(horizontal: .leading, vertical: .firstTextBaseline)) {
            if isChanged {
                Circle()
                    .fill(.tint)
                    .frame(width: SettingRowMetrics.changedDot, height: SettingRowMetrics.changedDot)
                    .offset(x: -(SettingRowMetrics.changedDot + SettingRowMetrics.changedDotGap))
                    .accessibilityHidden(true)
                    .help(SettingRowStrings.changed)
            }
        }
    }

    /// "Reset to Default" in the row's context menu (disabled at the default) and as a VoiceOver action (offered only
    /// when there is something to reset), plus the hint "Changed from the default" while it differs.
    func crannyResetToDefault(isDefault: Bool, reset: @escaping @MainActor () -> Void) -> some View {
        crannyResetToDefault(isDefault: isDefault, reset: reset) { EmptyView() }
    }

    /// `crannyResetToDefault(isDefault:reset:)` with the row's own context-menu items above "Reset to Default".
    func crannyResetToDefault<Menu: View>(isDefault: Bool, reset: @escaping @MainActor () -> Void,
                                          @ViewBuilder menu: () -> Menu) -> some View {
        modifier(ResetToDefaultModifier(isDefault: isDefault, reset: reset, menu: menu()))
    }
}

struct ResetToDefaultModifier<Menu: View>: ViewModifier {
    let isDefault: Bool
    let reset: @MainActor () -> Void
    let menu: Menu

    func body(content: Content) -> some View {
        content
            .contextMenu {
                if Menu.self != EmptyView.self {
                    menu
                    Divider()
                }
                Button(action: reset) { SettingRowStrings.resetToDefault }
                    .disabled(isDefault)
            }
            .accessibilityActions {
                if !isDefault {
                    Button(action: reset) { SettingRowStrings.resetToDefault }
                }
            }
            .accessibilityHint(isDefault ? Text(verbatim: "") : SettingRowStrings.changed)
    }
}

/// The convention's copy, from Core's catalog (one translation for every pane).
nonisolated enum SettingRowStrings {
    static var resetToDefault: Text {
        Text("Reset to Default", bundle: .module, comment: "Settings: row context menu item and VoiceOver action")
    }
    static var changed: Text {
        Text("Changed from the default", bundle: .module,
             comment: "Settings: VoiceOver hint of a row whose value differs from its default, and the tooltip of its dot")
    }
}

// MARK: - Permission status (DESIGN.md §11.1)

/// Granted (green) · Not yet · Denied (red) · Restricted (red) · Unknown: the text carries the meaning, the colour
/// repeats it. One mapping for Settings ▸ Permissions and every module pane that shows a permission.
public struct PermissionStatusPill: View {
    private let status: PermissionStatus

    /// A pill for `status`.
    public init(status: PermissionStatus) { self.status = status }

    /// The pill.
    public var body: some View {
        let title = Self.title(status)
        let color = Self.color(status)
        Text(verbatim: title)
            .font(.caption.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(color.opacity(0.14), in: Capsule(style: .continuous))
            .accessibilityLabel(Text("Status: \(title)", bundle: .module,
                                     comment: "Settings: VoiceOver label of a permission status pill; the argument is the status"))
    }

    /// The pill's text.
    public static func title(_ status: PermissionStatus) -> String {
        switch status {
        case .granted: String(localized: "Granted", bundle: .module, comment: "Settings: permission status pill")
        case .notDetermined: String(localized: "Not yet", bundle: .module, comment: "Settings: permission status pill (never asked)")
        case .denied: String(localized: "Denied", bundle: .module, comment: "Settings: permission status pill")
        case .restricted: String(localized: "Restricted", bundle: .module,
                                 comment: "Settings: permission status pill (blocked by a configuration profile)")
        case .unknown: String(localized: "Unknown", bundle: .module, comment: "Settings: permission status pill (macOS cannot tell yet)")
        }
    }

    /// Green for granted, red for denied or restricted, secondary otherwise (never the only cue).
    public static func color(_ status: PermissionStatus) -> Color {
        switch status {
        case .granted: .green
        case .denied, .restricted: .red
        case .notDetermined, .unknown: .secondary
        }
    }
}

#Preview("Setting rows and status pills") {
    let settings = CrannyServices.preview().settings
    settings[CoreSettings.hoverDelay] = .long
    return Form {
        Picker(selection: settings.binding(CoreSettings.hoverDelay)) {
            ForEach(HoverIntent.Delay.allCases, id: \.self) { Text(verbatim: $0.rawValue).tag($0) }
        } label: { Text(verbatim: "Hover delay (changed)") }
            .crannySettingRow(settings, CoreSettings.hoverDelay)
        Toggle(isOn: settings.binding(CoreSettings.closeOnLeave)) { Text(verbatim: "Close on leave (default)") }
            .crannySettingRow(settings, CoreSettings.closeOnLeave)
        HStack {
            ForEach([PermissionStatus.granted, .notDetermined, .denied, .restricted, .unknown], id: \.self) {
                PermissionStatusPill(status: $0)
            }
        }
    }
    .formStyle(.grouped)
    .frame(width: 520, height: 220)
}
