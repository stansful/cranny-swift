// CrannyHUD/UI/HUDSettingsPane.swift — Settings ▸ HUD (DESIGN.md §11.1, ARCHITECTURE.md §10.10): Replace the
// system HUD (needs Accessibility; status pill and why) · Volume / Brightness / Keyboard backlight · Colors ·
// Show value · Show output device · Duration. The Settings stage above it shows the HUD (`previewState: .hud`).
//
// Turning "Replace the system HUD" on while Accessibility is missing asks for it then (the one place outside
// onboarding that does, §7.13). Whenever the toggle is on but Cranny leaves the keys to macOS, the pane says why:
// no Accessibility (with a link to System Settings), the HUD activity off in Live Activities (with a link there),
// or a tap macOS refused (`HUDPaneStatus`).
import AppKit
import CrannyCore
import Foundation
import SwiftUI

/// What Settings ▸ HUD explains under its main toggle. Pure, so every state is tested: each one in which the toggle
/// is on but macOS keeps its own HUD gives the reason (D10: never two HUDs, and never none without saying why).
nonisolated enum HUDPaneStatus: Equatable {
    /// Accessibility is missing: no tap, whatever the toggle says.
    case needsAccessibility
    /// "Replace the system HUD" is off.
    case off
    /// On and granted, but the HUD activity is off in Settings ▸ Live Activities: the keys go to macOS.
    case activityDisabled
    /// The key tap runs: Cranny draws the HUD.
    case running
    /// macOS refused the tap although Accessibility was reported granted.
    case tapFailed
    /// On, granted and enabled, but no tap yet, or none of Volume / Brightness / Keyboard backlight is on (the
    /// rows below show that).
    case idle

    init(granted: Bool, replacing: Bool, activityEnabled: Bool, tapRunning: Bool, tapFailed: Bool) {
        self = if !granted { .needsAccessibility }
               else if !replacing { .off }
               else if !activityEnabled { .activityDisabled }
               else if tapRunning { .running }
               else if tapFailed { .tapFailed }
               else { .idle }
    }
}

struct HUDSettingsPane: View {
    let settings: SettingsStore
    let permissions: PermissionsCenter
    /// Opens Settings ▸ Live Activities.
    let app: any AppControl
    /// nil in previews: status comes from the permission alone.
    var controller: HUDController?
    /// Previews only: the Accessibility status to show instead of this Mac's (a preview process has no grant).
    var previewAccessibility: PermissionStatus?
    @State private var competingApps: [String] = []

    var body: some View {
        let replacing = settings[HUDSettings.replaceSystemHUD]
        let status = HUDPaneStatus(granted: accessibilityStatus == .granted, replacing: replacing,
                                   activityEnabled: HUDActivity.isEnabled(in: settings),
                                   tapRunning: controller?.isTapRunning ?? false, tapFailed: controller?.tapFailed ?? false)
        Form {
            Section {
                replaceRow
                accessibilityRow(status: status)
                if status == .activityDisabled { activityDisabledRow }
                if replacing, !competingApps.isEmpty { competingRow }
            } footer: {
                Text("Cranny draws its HUD only when it can hide the one macOS shows. Without Accessibility, macOS keeps its own HUD and Cranny shows none.",
                     bundle: .module, comment: "Settings ▸ HUD: footnote under Replace the system HUD (why Accessibility is needed)")
                    .font(.caption).foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
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
        Toggle(isOn: Binding(get: { settings[HUDSettings.replaceSystemHUD] }, set: { setReplacing($0) })) {
            FootnotedLabel(title: Text("Replace the system HUD", bundle: .module, comment: "Settings ▸ HUD: main toggle"),
                           footnote: Text("Volume, brightness and keyboard backlight levels appear in the notch.", bundle: .module,
                                          comment: "Settings ▸ HUD: footnote under Replace the system HUD"))
        }
        .resettable(HUDSettings.replaceSystemHUD, in: settings)
    }

    private var accessibilityStatus: PermissionStatus { previewAccessibility ?? permissions.status(.accessibility) }

    private func accessibilityRow(status paneStatus: HUDPaneStatus) -> some View {
        let status = accessibilityStatus
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
            FootnotedLabel(title: Text(PermissionKind.accessibility.title), footnote: accessibilityFootnote(paneStatus))
        }
    }

    private func accessibilityFootnote(_ status: HUDPaneStatus) -> Text? {
        switch status {
        case .needsAccessibility:
            Text("Turn on Cranny in Privacy & Security ▸ Accessibility, then come back here.", bundle: .module,
                 comment: "Settings ▸ HUD: footnote while Accessibility is not granted")
        case .running:
            Text("Cranny handles the keys now.", bundle: .module, comment: "Settings ▸ HUD: footnote while the HUD replacement is active")
        case .tapFailed:
            Text("macOS did not hand the keys to Cranny. Try turning the HUD off and on.", bundle: .module,
                 comment: "Settings ▸ HUD: footnote when the key tap could not start although Accessibility is granted")
        case .off, .activityDisabled, .idle:
            nil
        }
    }

    /// The HUD activity is off in Settings ▸ Live Activities, so every key goes to macOS: say so and link there.
    private var activityDisabledRow: some View {
        LabeledContent {
            Button {
                app.openSettings(.liveActivities)
            } label: {
                Text("Live Activities Settings…", bundle: .module, comment: "Settings ▸ HUD: button that opens Settings ▸ Live Activities")
            }
        } label: {
            FootnotedLabel(title: Text("The HUD is off in Live Activities", bundle: .module,
                                       comment: "Settings ▸ HUD: row shown while the HUD activity is turned off in Settings ▸ Live Activities"),
                           footnote: Text("macOS shows its own HUD until you turn it back on there.", bundle: .module,
                                          comment: "Settings ▸ HUD: footnote under The HUD is off in Live Activities"))
        }
    }

    private var competingRow: some View {
        let names = competingApps.map(\.crannyIsolated).formatted(.list(type: .and))     // each name in its own direction
        return Label {
            Group {
                if competingApps.count == 1 {
                    Text("\(names) can also take the volume and brightness keys. If Cranny’s HUD doesn’t appear, turn off the HUD in that app.",
                         bundle: .module, comment: "Settings ▸ HUD: warning while ONE known app with its own HUD runs; argument is its name, such as MonitorControl")
                } else {
                    Text("\(names) can also take the volume and brightness keys. If Cranny’s HUD doesn’t appear, turn off the HUD in these apps.",
                         bundle: .module, comment: "Settings ▸ HUD: warning while SEVERAL known apps with their own HUD run; argument is a list of names, such as “MonitorControl and SoundSource”")
                }
            }
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
                       in: HUDSettings.durationRange)          // a stepped slider would draw 23 ticks
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
        Self.userSetReplacing(on, settings: settings)
        guard on, permissions.status(.accessibility) != .granted else { return }
        Task { await permissions.request(.accessibility) }     // the system prompt, then 1.5-s polling for 2 min
    }

    /// The user's own switch. An explicit off is remembered, so a later Accessibility grant (which otherwise turns
    /// the HUD on, `HUDController`) keeps it off; switching it on clears that.
    static func userSetReplacing(_ on: Bool, settings: SettingsStore) {
        settings[HUDSettings.replaceSystemHUD] = on
        settings[HUDSettings.turnedOffByUser] = !on
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
    return HUDSettingsPane(settings: services.settings, permissions: services.permissions, app: services.app)
        .frame(width: 620, height: 640)
}

#Preview("Settings ▸ HUD · off in Live Activities") {
    let services = CrannyServices.preview()
    services.settings[HUDSettings.replaceSystemHUD] = true
    services.settings[CoreSettings.activityPreferences] = [.hud: ActivityPreference(isEnabled: false, peeksOnChange: false)]
    return HUDSettingsPane(settings: services.settings, permissions: services.permissions, app: services.app,
                           previewAccessibility: .granted)
        .frame(width: 620, height: 640)
}

#Preview("Settings ▸ HUD · off") {
    let services = CrannyServices.preview()
    return HUDSettingsPane(settings: services.settings, permissions: services.permissions, app: services.app)
        .frame(width: 620, height: 640)
}
