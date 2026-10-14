// CrannySystemActivities/UI/SystemOptionsViews.swift — the module's rows in Settings ▸ Live Activities
// (`registry.add(activity:…, options:)`): thresholds under Low battery, "Show all Bluetooth devices" under
// Bluetooth devices (DESIGN.md §11.1). Settings is an ordinary window: system controls and colours, grouped-form
// conventions of §11.3 (menu pickers, small switches, `.secondary` footnotes, accent dot + Reset to Default).
import CrannyCore
import SwiftUI

/// Low battery: "First warning" (Off, 15–50 %) and "Final warning" (5–20 %, stays until power is connected).
struct LowBatteryOptionsView: View {
    static let firstWarningChoices = [15, 20, 25, 30, 40, 50]
    static let finalWarningChoices = [5, 10, 15, 20]

    let settings: SettingsStore

    var body: some View {
        let key = SystemSettings.lowBatteryThresholds
        let thresholds = LowBatteryThresholds(settings[key])
        Group {
            Picker(selection: Binding(get: { thresholds.firstWarning ?? 0 },
                                      set: { settings[key] = thresholds.replacingFirstWarning($0 == 0 ? nil : $0).values })) {
                Text(verbatim: SystemCopy.off).tag(0)
                ForEach(Self.firstWarningChoices.filter { $0 > (thresholds.final ?? 0) }, id: \.self) { value in
                    Text(verbatim: SystemCopy.percent(value)).tag(value)
                }
            } label: {
                OptionLabel(title: SystemCopy.firstWarning, isDefault: settings.isDefault(key))
            }
            Picker(selection: Binding(get: { thresholds.final ?? 10 },
                                      set: { settings[key] = thresholds.replacingFinal($0).values })) {
                ForEach(Self.finalWarningChoices, id: \.self) { value in
                    Text(verbatim: SystemCopy.percent(value)).tag(value)
                }
            } label: {
                OptionLabel(title: SystemCopy.finalWarning, footnote: SystemCopy.finalWarningFootnote, isDefault: settings.isDefault(key))
            }
        }
        .pickerStyle(.menu)
        .contextMenu {
            Button { settings.reset(key) } label: { Text(verbatim: SystemCopy.resetToDefault) }
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
                Button { settings.reset(key) } label: { Text(verbatim: SystemCopy.resetToDefault) }
            }
            if settings[key] && (status == .denied || status == .restricted) {
                LabeledContent {
                    Button { permissions.openSystemSettings(.bluetooth) } label: { Text(verbatim: SystemCopy.openSystemSettings) }
                } label: {
                    Label { Text(verbatim: SystemCopy.bluetoothAccessOff) } icon: {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    }
                }
            }
        }
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
