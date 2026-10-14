// CrannySettingsUI/Panes/GeneralPane.swift — Settings ▸ General (DESIGN.md §11.1): launch at login, where Cranny shows
// (per-display table), how it opens and closes, full-screen apps and exclusions, Demo mode, sounds, the menu bar
// icon, updates and Reset All. Settings apply instantly (ARCHITECTURE D14); side effects follow the keys.
import CrannyCore
import Foundation
import SwiftUI

struct GeneralPane: View {
    let registry: ModuleRegistry
    @Environment(ResetAllController.self) private var resetAll: ResetAllController?
    @State private var confirmingReset = false

    private var settings: SettingsStore { registry.services.settings }

    var body: some View {
        SettingsForm(.general) {
            Section {
                LoginItemRow(app: registry.services.app)
            }
            DisplaySection(settings: settings)
            Section {
                ChoiceRow(GeneralRows.openMode, settings: settings, key: CoreSettings.openMode, choices: [
                    Choice(value: .hover, label: String(localized: "Hover", bundle: .module, comment: "Settings ▸ General ▸ Open Cranny with: option")),
                    Choice(value: .click, label: String(localized: "Click", bundle: .module, comment: "Settings ▸ General ▸ Open Cranny with: option")),
                    Choice(value: .shortcutOnly, label: String(localized: "Shortcut only", bundle: .module, comment: "Settings ▸ General ▸ Open Cranny with: option")),
                ])
                ChoiceRow(GeneralRows.hoverDelay, settings: settings, key: CoreSettings.hoverDelay,
                          choices: HoverIntent.Delay.allCases.map { Choice(value: $0, label: Self.title(of: $0)) },
                          footnote: String(localized: "How long the pointer rests on the notch before Cranny opens.", bundle: .module,
                                           comment: "Settings ▸ General: footnote of Hover delay"))
                    .disabled(settings[CoreSettings.openMode] != .hover)
                ToggleRow(info: GeneralRows.holdOption, settings: settings, key: CoreSettings.holdOptionToPass,
                          footnote: String(localized: "Hold Option to move across the notch without opening it.", bundle: .module,
                                           comment: "Settings ▸ General: footnote of Hold ⌥ to pass over"))
                ToggleRow(info: GeneralRows.closeOnLeave, settings: settings, key: CoreSettings.closeOnLeave,
                          footnote: String(localized: "Cranny waits a moment before closing, and never closes while you type or drag.",
                                           bundle: .module, comment: "Settings ▸ General: footnote of Close when the pointer leaves"))
                ChoiceRow(GeneralRows.inactivityTimeout, settings: settings, key: CoreSettings.openInactivityTimeout,
                          choices: [0, 5, 10, 15, 30, 60].map { Choice(value: Double($0), label: SettingsFormat.timeout(Double($0))) },
                          style: .menu)
            } header: {
                Text("Opening and closing", bundle: .module, comment: "Settings ▸ General: section header")
            }
            Section {
                ChoiceRow(GeneralRows.fullScreen, settings: settings, key: CoreSettings.fullScreenPolicy, choices: [
                    Choice(value: .hideAll, label: String(localized: "Hide", bundle: .module, comment: "Settings ▸ General ▸ In full-screen apps: option")),
                    Choice(value: .alertsAndHUD, label: String(localized: "Alerts and HUD only", bundle: .module, comment: "Settings ▸ General ▸ In full-screen apps: option")),
                    Choice(value: .showAll, label: String(localized: "Show", bundle: .module, comment: "Settings ▸ General ▸ In full-screen apps: option")),
                ], footnote: String(localized: "Opening there needs a longer rest of the pointer.", bundle: .module,
                                    comment: "Settings ▸ General: footnote of In full-screen apps"), style: .menu)
                ExcludedAppsEditor(settings: settings)
                HideHandleRow(settings: settings)
            } header: {
                Text("Full screen and apps", bundle: .module, comment: "Settings ▸ General: section header")
            }
            Section {
                ToggleRow(info: GeneralRows.demoMode, settings: settings, key: CoreSettings.demoMode,
                          footnote: String(localized: "For screen sharing: keeps Cranny open, shows it over full-screen apps and mutes its sounds.",
                                           bundle: .module, comment: "Settings ▸ General: footnote of Demo mode"))
                ToggleRow(info: GeneralRows.redactCalendar, settings: settings, key: CoreSettings.demoRedactsCalendar)
                    .disabled(!settings[CoreSettings.demoMode])
                    .padding(.leading, 16)
                ToggleRow(info: GeneralRows.uiSounds, settings: settings, key: CoreSettings.uiSounds,
                          footnote: String(localized: "A soft pop when a file is caught and a tink when a to-do is done.", bundle: .module,
                                           comment: "Settings ▸ General: footnote of UI sounds"))
                ToggleRow(info: GeneralRows.menuBarIcon, settings: settings, key: CoreSettings.showsMenuBarIcon,
                          footnote: String(localized: "When hidden, open Cranny again from Finder or Spotlight to reach Settings.", bundle: .module,
                                           comment: "Settings ▸ General: footnote of Show menu bar icon"))
            } header: {
                Text("Demo mode and sounds", bundle: .module, comment: "Settings ▸ General: section header")
            }
            UpdatesSection(settings: settings, app: registry.services.app)
            Section {
                Button {
                    confirmingReset = true
                } label: {
                    Text(verbatim: GeneralRows.resetAll.title).foregroundStyle(.red)
                }
                .searchTarget(GeneralRows.resetAll)
            } footer: {
                Text("Notes, to-dos and tray files are kept.", bundle: .module, comment: "Settings ▸ General: footnote of Reset All Settings")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .alert(Text("Reset all settings?", bundle: .module, comment: "Settings ▸ General: Reset All confirmation title"),
               isPresented: $confirmingReset) {
            Button(role: .destructive) {
                resetAll?.resetAll()
            } label: {
                Text("Reset All", bundle: .module, comment: "Settings ▸ General: Reset All confirmation button")
            }
            Button(role: .cancel) {} label: {
                Text("Cancel", bundle: .module, comment: "Settings: cancel button of a confirmation")
            }
        } message: {
            Text("Every Cranny setting returns to its default. You can undo this for 10 seconds.", bundle: .module,
                 comment: "Settings ▸ General: Reset All confirmation message")
        }
    }

    /// "Instant", "120 ms", "220 ms", "450 ms" (DESIGN.md §11.1).
    static func title(of delay: HoverIntent.Delay) -> String {
        delay == .instant ? String(localized: "Instant", bundle: .module, comment: "Settings: option with no delay or no animation (Hover delay, Motion)")
                          : SettingsFormat.milliseconds(delay.seconds)
    }
}

/// "Hide the handle when idle" with its delay (displays without a notch, DESIGN.md §3.5).
private struct HideHandleRow: View {
    let settings: SettingsStore
    var body: some View {
        let isDefault = settings.isDefault(CoreSettings.hideHandleWhenIdle) && settings.isDefault(CoreSettings.handleIdleDelay)
        LabeledContent {
            HStack(spacing: 8) {
                Picker(selection: settings.binding(CoreSettings.handleIdleDelay)) {
                    ForEach([3.0, 5, 10, 20, 30, 60], id: \.self) { seconds in
                        Text(verbatim: SettingsFormat.seconds(seconds)).tag(seconds)
                    }
                } label: {
                    Text("Delay", bundle: .module, comment: "Settings ▸ General: delay before the idle handle hides (VoiceOver)")
                }
                .labelsHidden()
                .fixedSize()
                .disabled(!settings[CoreSettings.hideHandleWhenIdle])
                Toggle(isOn: settings.binding(CoreSettings.hideHandleWhenIdle)) { Text(verbatim: GeneralRows.hideWhenIdle.title) }
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }
        } label: {
            RowLabel(title: GeneralRows.hideWhenIdle.title,
                     footnote: String(localized: "On displays without a notch, the handle fades out after this long without activity.",
                                      bundle: .module, comment: "Settings ▸ General: footnote of Hide the handle when idle"),
                     isChanged: !isDefault)
        }
        .settingRow(GeneralRows.hideWhenIdle, isDefault: isDefault) {
            settings.reset(CoreSettings.hideHandleWhenIdle)
            settings.reset(CoreSettings.handleIdleDelay)
        }
    }
}

#Preview("General") {
    GeneralPane(registry: ModuleRegistry(services: .preview()))
        .frame(width: 650, height: 900)
}
