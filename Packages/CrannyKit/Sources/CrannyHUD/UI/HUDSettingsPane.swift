// CrannyHUD/UI/HUDSettingsPane.swift — Settings ▸ HUD (DESIGN.md §11.1, ARCHITECTURE.md §10.10): Replace the
// system HUD (needs Accessibility; status pill and why) · Volume / Brightness / Keyboard backlight · Colors ·
// Show value · Show output device · Duration. The Settings stage above it shows the HUD (`previewState: .hud`).
//
// Turning "Replace the system HUD" on while Accessibility is missing asks for it then (the one place outside
// onboarding that does, §7.13). Without the grant the pane says why there is no HUD and links to System Settings.
import AppKit
import CrannyCore
import Foundation
import SwiftUI

struct HUDSettingsPane: View {
    let settings: SettingsStore
    let permissions: PermissionsCenter
    /// nil in previews: status comes from the permission alone.
    var controller: HUDController?
    @State private var competingApps: [String] = []

    var body: some View {
        let replacing = settings[HUDSettings.replaceSystemHUD]
        Form {
            Section {
                replaceRow
                accessibilityRow(replacing: replacing)
                if replacing, !competingApps.isEmpty { competingRow }
            } footer: {
                Text("Cranny draws its HUD only when it can hide the one macOS shows. Without Accessibility, macOS keeps its own HUD and Cranny shows none.",
                     bundle: .module, comment: "Settings ▸ HUD: footnote under Replace the system HUD (why Accessibility is needed)")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                Toggle(isOn: settings.binding(HUDSettings.volume)) { Text(HUDKind.volume.title) }
                    .resettable(HUDSettings.volume, in: settings)
                Toggle(isOn: settings.binding(HUDSettings.brightness)) {
                    FootnotedLabel(title: Text(HUDKind.brightness.title),
                                   footnote: Text("Built-in display only. Other displays keep the macOS HUD.", bundle: .module,
                                                  comment: "Settings ▸ HUD: footnote under Brightness"))
                }
                .resettable(HUDSettings.brightness, in: settings)
                Toggle(isOn: settings.binding(HUDSettings.keyboardBacklight)) {
                    FootnotedLabel(title: Text("Keyboard backlight", bundle: .module, comment: "Settings ▸ HUD: toggle for the keyboard backlight keys"),
                                   footnote: Text("For keyboards with backlight keys.", bundle: .module,
                                                  comment: "Settings ▸ HUD: footnote under Keyboard backlight"))
                }
                .resettable(HUDSettings.keyboardBacklight, in: settings)
            } header: {
                Text("Show the HUD for", bundle: .module, comment: "Settings ▸ HUD: section header above Volume / Brightness / Keyboard backlight")
            }
            .disabled(!replacing)

            Section {
                colorsRow
                Toggle(isOn: settings.binding(HUDSettings.showsValue)) {
                    FootnotedLabel(title: Text("Show value", bundle: .module, comment: "Settings ▸ HUD: toggle that shows the level as a number"),
                                   footnote: Text("Always shown with Differentiate without color.", bundle: .module,
                                                  comment: "Settings ▸ HUD: footnote under Show value (macOS Accessibility ▸ Display setting)"))
                }
                .resettable(HUDSettings.showsValue, in: settings)
                Toggle(isOn: settings.binding(HUDSettings.showsOutputDevice)) {
                    FootnotedLabel(title: Text("Show output device", bundle: .module, comment: "Settings ▸ HUD: toggle"),
                                   footnote: Text("After the sound output changes, the next volume HUD shows the new device.", bundle: .module,
                                                  comment: "Settings ▸ HUD: footnote under Show output device"))
                }
                .resettable(HUDSettings.showsOutputDevice, in: settings)
                durationRow
            } header: {
                Text("Style", bundle: .module, comment: "Settings ▸ HUD: section header above Colors, Show value, Show output device, Duration")
            }
            .disabled(!replacing)
        }
        .formStyle(.grouped)
        .toggleStyle(.switch)
        .controlSize(.small)
        .onAppear {
            permissions.refresh()
            competingApps = CompetingHUDApps.running(in: NSWorkspace.shared.runningApplications.map(\.bundleIdentifier))
        }
    }

    // MARK: Rows

    private var replaceRow: some View {
        Toggle(isOn: Binding(get: { settings[HUDSettings.replaceSystemHUD] }, set: setReplacing)) {
            FootnotedLabel(title: Text("Replace the system HUD", bundle: .module, comment: "Settings ▸ HUD: main toggle"),
                           footnote: Text("Volume, brightness and keyboard backlight levels appear in the notch.", bundle: .module,
                                          comment: "Settings ▸ HUD: footnote under Replace the system HUD"))
        }
        .resettable(HUDSettings.replaceSystemHUD, in: settings)
    }

    private func accessibilityRow(replacing: Bool) -> some View {
        let status = permissions.status(.accessibility)
        return LabeledContent {
            HStack(spacing: 8) {
                PermissionStatusPill(status: status)
                if status != .granted {
                    Button {
                        permissions.openSystemSettings(.accessibility)
                    } label: {
                        Text("Open System Settings", bundle: .module, comment: "Settings ▸ HUD: button that opens Privacy & Security ▸ Accessibility")
                    }
                }
            }
        } label: {
            FootnotedLabel(title: Text(PermissionKind.accessibility.title), footnote: accessibilityFootnote(status: status, replacing: replacing))
        }
    }

    private func accessibilityFootnote(status: PermissionStatus, replacing: Bool) -> Text? {
        if status != .granted {
            return Text("Turn on Cranny in Privacy & Security ▸ Accessibility, then come back here.", bundle: .module,
                        comment: "Settings ▸ HUD: footnote while Accessibility is not granted")
        }
        guard replacing else { return nil }
        return controller?.isTapRunning == false
            ? Text("macOS did not hand the keys to Cranny. Try turning the HUD off and on.", bundle: .module,
                   comment: "Settings ▸ HUD: footnote when the key tap could not start although Accessibility is granted")
            : Text("Cranny handles the keys now.", bundle: .module, comment: "Settings ▸ HUD: footnote while the HUD replacement is active")
    }

    private var competingRow: some View {
        let names = competingApps.formatted(.list(type: .and))
        return Label {
            Text("\(names) can also take the volume and brightness keys. If Cranny's HUD doesn't appear, turn off the HUD in that app.",
                 bundle: .module, comment: "Settings ▸ HUD: warning; argument is a list of app names such as MonitorControl")
                .font(.callout)
        } icon: {
            Image(systemName: "exclamationmark").foregroundStyle(.orange)
        }
    }

    private var colorsRow: some View {
        Picker(selection: settings.binding(HUDSettings.colors)) {
            Text("Mono", bundle: .module, comment: "Settings ▸ HUD ▸ Colors: white bar").tag(HUDColors.mono)
            Text("Accent", bundle: .module, comment: "Settings ▸ HUD ▸ Colors: bar in the accent colour").tag(HUDColors.accent)
            Text("Semantic", bundle: .module, comment: "Settings ▸ HUD ▸ Colors: a meaningful colour per kind (accent, yellow, blue)").tag(HUDColors.semantic)
        } label: {
            FootnotedLabel(title: Text("Colors", bundle: .module, comment: "Settings ▸ HUD: picker for the level bar's colour"),
                           footnote: settings[HUDSettings.colors] == .semantic
                               ? Text("Accent for volume, yellow for brightness, blue for the keyboard.", bundle: .module,
                                      comment: "Settings ▸ HUD: footnote explaining the Semantic colours")
                               : nil)
        }
        .pickerStyle(.segmented)
        .resettable(HUDSettings.colors, in: settings)
    }

    private var durationRow: some View {
        let seconds = HUDSettings.clampedDuration(settings[HUDSettings.duration])
        return LabeledContent {
            HStack(spacing: 10) {
                Slider(value: Binding(get: { seconds }, set: { settings[HUDSettings.duration] = ($0 * 10).rounded() / 10 }),
                       in: HUDSettings.durationRange)
                    .frame(minWidth: 160)
                    .accessibilityLabel(Text("Duration", bundle: .module, comment: "Settings ▸ HUD: how long the HUD stays"))
                    .accessibilityValue(Text(Self.durationText(seconds)))
                Text(Self.durationText(seconds))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 44, alignment: .trailing)
                    .accessibilityHidden(true)
            }
        } label: {
            FootnotedLabel(title: Text("Duration", bundle: .module, comment: "Settings ▸ HUD: how long the HUD stays"),
                           footnote: Text("How long the HUD stays after the last key press.", bundle: .module,
                                          comment: "Settings ▸ HUD: footnote under Duration"))
        }
        .resettable(HUDSettings.duration, in: settings)
    }

    private func setReplacing(_ on: Bool) {
        settings[HUDSettings.replaceSystemHUD] = on
        guard on, permissions.status(.accessibility) != .granted else { return }
        Task { await permissions.request(.accessibility) }     // the system prompt, then 1.5-s polling for 2 min
    }

    /// "1.5 s" in the user's locale.
    static func durationText(_ seconds: Double) -> String {
        Measurement(value: seconds, unit: UnitDuration.seconds)
            .formatted(.measurement(width: .narrow, numberFormatStyle: .number.precision(.fractionLength(1))))
    }
}

#Preview("Settings ▸ HUD · replacing") {
    let services = CrannyServices.preview()
    services.settings[HUDSettings.replaceSystemHUD] = true
    services.settings[HUDSettings.colors] = .semantic
    return HUDSettingsPane(settings: services.settings, permissions: services.permissions)
        .frame(width: 620, height: 640)
}

#Preview("Settings ▸ HUD · off") {
    let services = CrannyServices.preview()
    return HUDSettingsPane(settings: services.settings, permissions: services.permissions)
        .frame(width: 620, height: 640)
}
