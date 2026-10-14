// CrannySystemActivities/UI/SystemOptionsViews.swift — the module's rows in Settings ▸ Live Activities
// (`registry.add(activity:…, options:)`): thresholds under Low battery, "Show all Bluetooth devices" under
// Bluetooth devices (DESIGN.md §11.1). Settings is an ordinary window: system controls and colours, grouped-form
// conventions of §11.3 (segmented pickers for ≤ 4 choices, menus otherwise, small switches, `.secondary`
// footnotes, and per row an accent dot for a changed value and a Reset to Default that restores only that row).
import CrannyCore
import SwiftUI

/// Low battery: "First warning" (Off, 15–50 %: a menu) and "Final warning" (5–20 %: four choices, so a segmented
/// picker; it stays until power is connected). Both rows edit the one `lowBatteryThresholds` key, but each row's
/// dot and reset concern only its own value.
struct LowBatteryOptionsView: View {
    static let firstWarningChoices = [15, 20, 25, 30, 40, 50]
    static let finalWarningChoices = [5, 10, 15, 20]

    let settings: SettingsStore

    var body: some View {
        let key = SystemSettings.lowBatteryThresholds
        let thresholds = LowBatteryThresholds(settings[key])
        let defaults = LowBatteryThresholds.defaults
        Group {
            Picker(selection: Binding(get: { thresholds.firstWarning ?? 0 },
                                      set: { settings[key] = thresholds.replacingFirstWarning($0 == 0 ? nil : $0).values })) {
                Text(verbatim: SystemCopy.off).tag(0)
                ForEach(Self.firstWarningChoices.filter { $0 > (thresholds.final ?? 0) }, id: \.self) { value in
                    Text(verbatim: SystemCopy.percent(value)).tag(value)
                }
            } label: {
                OptionLabel(title: SystemCopy.firstWarning, isDefault: thresholds.firstWarning == defaults.firstWarning)
            }
            .pickerStyle(.menu)
            .contextMenu {
                ResetButton { settings[key] = thresholds.resettingFirstWarning().values }
            }
            Picker(selection: Binding(get: { thresholds.final ?? 10 },
                                      set: { settings[key] = thresholds.replacingFinal($0).values })) {
                ForEach(Self.finalWarningChoices, id: \.self) { value in
                    Text(verbatim: SystemCopy.percent(value)).tag(value)
                }
            } label: {
                OptionLabel(title: SystemCopy.finalWarning, footnote: SystemCopy.finalWarningFootnote,
                            isDefault: thresholds.final == defaults.final)
            }
            .pickerStyle(.segmented)
            .contextMenu {
                ResetButton { settings[key] = thresholds.resettingFinal().values }
            }
        }
    }
}

/// Bluetooth devices: the opt-in IOBluetooth path. Turning it on asks for Bluetooth access (an explicit
/// user action, §3.12); a denied access shows a way to System Settings instead.
struct BluetoothOptionsView: View {
    let settings: SettingsStore
    let permissions: PermissionsCenter

    var body: some View {
        let key = SystemSettings.showsAllBluetoothDevices
        let status = permissions.status(.bluetooth)
        Group {
            Toggle(isOn: Binding(get: { settings[key] }, set: { isOn in
                settings[key] = isOn
                if isOn && status == .notDetermined {
                    Task { await permissions.request(.bluetooth) }
                }
            })) {
                OptionLabel(title: SystemCopy.showAllDevices, footnote: SystemCopy.showAllDevicesFootnote, isDefault: settings.isDefault(key))
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .contextMenu {
                ResetButton { settings.reset(key) }
            }
            if settings[key] && (status == .denied || status == .restricted) {
                LabeledContent {
                    Button { permissions.openSystemSettings(.bluetooth) } label: { Text(verbatim: SystemCopy.openSystemSettings) }
                } label: {
                    Label { Text(verbatim: SystemCopy.bluetoothAccessOff) } icon: {
                        // The system's own warning sign: its multicolour rendering supplies the colours, adapting
                        // to Light/Dark and Increase Contrast like the rest of the window (no literal colour).
                        Image(systemName: "exclamationmark.triangle.fill")
                            .symbolRenderingMode(.multicolor)
                            .accessibilityHidden(true)
                    }
                }
            }
        }
    }
}

/// A row's context menu: Reset to Default (DESIGN.md §11.3).
private struct ResetButton: View {
    let reset: () -> Void
    var body: some View {
        Button(action: reset) { Text(verbatim: SystemCopy.resetToDefault) }
    }
}

/// A row label: the changed-value dot (6 pt, accent) before the title, and an optional `.secondary` footnote.
private struct OptionLabel: View {
    let title: String
    var footnote: String?
    let isDefault: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Circle().fill(.tint).frame(width: 6, height: 6)
                    .opacity(isDefault ? 0 : 1)
                    .accessibilityHidden(true)
                Text(verbatim: title)
            }
            if let footnote {
                Text(verbatim: footnote)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 12)
            }
        }
    }
}

#Preview("Live Activities options") {
    let services = CrannyServices.preview()
    services.settings[SystemSettings.lowBatteryThresholds] = [25, 10]
    return Form {
        Section(SystemCopy.lowBattery) { LowBatteryOptionsView(settings: services.settings) }
        Section(SystemCopy.bluetoothDevices) { BluetoothOptionsView(settings: services.settings, permissions: services.permissions) }
    }
    .formStyle(.grouped)
    .frame(width: 520, height: 360)
}
