// CrannySettingsUI/Panes/GesturesPane.swift — Settings ▸ Gestures (DESIGN.md §4.4, §11.1, §14.2): two-finger swipes on the
// notch (change track + invert, open and close, dismiss an activity), sensitivity, and haptic feedback with a
// "Feel it" button. Every haptic has a visual counterpart: the button's glyph bounces (not under Reduce Motion).
import CrannyCore
import Foundation
import SwiftUI

enum GesturesRows {
    static var trackSwipe: SettingsRowInfo {
        SettingsRowInfo(.gestures, "trackSwipe",
                        title: String(localized: "Swipe sideways to change track", bundle: .module, comment: "Settings ▸ Gestures: toggle"),
                        keywords: [String(localized: "trackpad", bundle: .module, comment: "Settings search: keyword for gestures")])
    }
    static var invert: SettingsRowInfo {
        SettingsRowInfo(.gestures, "invertTrackSwipe",
                        title: String(localized: "Invert direction", bundle: .module, comment: "Settings ▸ Gestures: toggle under Swipe sideways"))
    }
    static var openClose: SettingsRowInfo {
        SettingsRowInfo(.gestures, "swipeOpenClose",
                        title: String(localized: "Swipe down to open, up to close", bundle: .module, comment: "Settings ▸ Gestures: toggle"))
    }
    static var dismiss: SettingsRowInfo {
        SettingsRowInfo(.gestures, "swipeToDismiss",
                        title: String(localized: "Swipe up to dismiss", bundle: .module, comment: "Settings ▸ Live Activities and Gestures: toggle"))
    }
    static var sensitivity: SettingsRowInfo {
        SettingsRowInfo(.gestures, "sensitivity",
                        title: String(localized: "Sensitivity", bundle: .module, comment: "Settings ▸ Gestures: slider"))
    }
    static var haptics: SettingsRowInfo {
        SettingsRowInfo(.gestures, "haptics",
                        title: String(localized: "Haptic feedback", bundle: .module, comment: "Settings ▸ Gestures: toggle"),
                        keywords: [String(localized: "vibration", bundle: .module, comment: "Settings search: keyword for Haptic feedback")])
    }

    static var all: [SettingsRowInfo] { [trackSwipe, invert, openClose, dismiss, sensitivity, haptics] }
}

struct GesturesPane: View {
    let registry: ModuleRegistry
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var feltCount = 0

    private var settings: SettingsStore { registry.services.settings }

    var body: some View {
        SettingsForm(.gestures) {
            Section {
                ToggleRow(info: GesturesRows.trackSwipe, settings: settings, key: CoreSettings.trackSwipe,
                          footnote: String(localized: "Two fingers left or right over the playing song.", bundle: .module,
                                           comment: "Settings ▸ Gestures: footnote of Swipe sideways to change track"))
                ToggleRow(info: GesturesRows.invert, settings: settings, key: CoreSettings.invertTrackSwipe)
                    .disabled(!settings[CoreSettings.trackSwipe])
                    .padding(.leading, 16)
                ToggleRow(info: GesturesRows.openClose, settings: settings, key: CoreSettings.swipeOpenClose)
                ToggleRow(info: GesturesRows.dismiss, settings: settings, key: CoreSettings.swipeToDismiss,
                          footnote: String(localized: "Also set in Live Activities.", bundle: .module,
                                           comment: "Settings ▸ Gestures: footnote of Swipe up to dismiss"))
                SliderRow(GesturesRows.sensitivity, settings: settings, key: CoreSettings.gestureSensitivity, range: 0.5...1.5, step: 0.1,
                          footnote: String(localized: "Higher needs less finger travel.", bundle: .module,
                                           comment: "Settings ▸ Gestures: footnote of Sensitivity")) { SettingsFormat.percent($0) }
            } header: {
                Text("Swipes on the notch", bundle: .module, comment: "Settings ▸ Gestures: section header")
            } footer: {
                if !registry.services.environment.hasTrackpad {
                    Text("Connect a trackpad to use gestures. Every gesture also has a click or key.", bundle: .module,
                         comment: "Settings ▸ Gestures: footer when no trackpad is present")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            Section {
                Toggle(isOn: settings.binding(CoreSettings.haptics)) {
                    HStack(spacing: 12) {
                        RowLabel(title: GesturesRows.haptics.title,
                                 footnote: String(localized: "You feel it while a finger rests on a Force Touch trackpad.", bundle: .module,
                                                  comment: "Settings ▸ Gestures: footnote of Haptic feedback"),
                                 isChanged: !settings.isDefault(CoreSettings.haptics))
                        Spacer(minLength: 8)
                        Button {
                            registry.services.haptics.play(.generic)
                            feltCount += 1
                        } label: {
                            Label {
                                Text("Feel It", bundle: .module, comment: "Settings ▸ Gestures: button that plays a haptic")
                            } icon: {
                                Image(systemName: "hand.draw.fill")
                                    .symbolEffect(.bounce, value: reduceMotion ? 0 : feltCount)
                            }
                        }
                        .disabled(!settings[CoreSettings.haptics])
                    }
                }
                .toggleStyle(.switch)
                .controlSize(.small)
                .settingRow(GesturesRows.haptics, settings: settings, key: CoreSettings.haptics)
            }
        }
    }
}

#Preview("Gestures") {
    GesturesPane(registry: ModuleRegistry(services: .preview()))
        .frame(width: 650, height: 520)
}
