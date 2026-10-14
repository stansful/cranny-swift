// CrannyTimer/UI/TimerOptionsView.swift — the Timer's options (DESIGN.md §11.1: "Timer presets and sound" in
// Layout & Widgets and the card's ⋯ menu; "Peek at one minute left" under Timer in Live Activities).
// These render in ordinary windows and popovers, so they use system controls. Settings apply instantly (D14).
import CrannyCore
import Foundation
import SwiftUI

/// Four preset steppers (whole minutes) and the alert sound.
struct TimerOptionsView: View {
    let settings: SettingsStore
    @State private var preview = SystemTimerSound()

    /// Minutes a preset can take in the editor (presets are stored in seconds; typed timers can be shorter or longer).
    static let presetMinutes = 1...180

    var body: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: Space.m, verticalSpacing: Space.s) {
            GridRow {
                Text(TimerCopy.presetsTitle).font(.headline)
                    .gridCellColumns(2)
            }
            ForEach(0..<TimerSettings.maximumPresets, id: \.self) { index in
                GridRow {
                    Text(TimerCopy.presetLabel(index + 1))
                    Stepper(value: presetBinding(index), in: Self.presetMinutes) {
                        Text(TimerFormat.short(presetBinding(index).wrappedValue * 60)).monospacedDigit()
                    }
                }
            }
            Divider().gridCellColumns(2)
            GridRow {
                Text(TimerCopy.soundTitle)
                Picker(selection: soundBinding) {
                    Text(TimerCopy.noSound).tag(String?.none)
                    Divider()
                    ForEach(Self.soundChoices(), id: \.fileName) { sound in
                        Text(verbatim: sound.name).tag(String?.some(sound.fileName))
                    }
                } label: {
                    Text(TimerCopy.soundTitle)
                }
                .labelsHidden()
                .fixedSize()
            }
        }
        .padding(Space.l)
        .onDisappear { preview.stop() }
    }

    /// Preset `index` in whole minutes; writing keeps the other presets and pads a short list with the defaults.
    private func presetBinding(_ index: Int) -> Binding<Int> {
        Binding {
            let presets = settings[TimerSettings.presets]
            let seconds = index < presets.count ? presets[index] : TimerSettings.presets.defaultValue[index]
            return min(max(Int((Double(seconds) / 60).rounded()), Self.presetMinutes.lowerBound), Self.presetMinutes.upperBound)
        } set: { minutes in
            var presets = settings[TimerSettings.presets]
            let defaults = TimerSettings.presets.defaultValue
            while presets.count < TimerSettings.maximumPresets { presets.append(defaults[presets.count]) }
            presets[index] = minutes * 60
            settings[TimerSettings.presets] = Array(presets.prefix(TimerSettings.maximumPresets))
        }
    }

    /// The system sounds under the names System Settings ▸ Sound shows (already localized by `TimerCopy`), in
    /// that pane's order: alphabetical by shown name. `name` is replaceable for tests.
    static func soundChoices(named name: (String) -> String = TimerCopy.soundName) -> [(fileName: String, name: String)] {
        TimerSettings.systemSounds
            .map { (fileName: $0, name: name($0)) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// The sound; choosing one plays it once, as System Settings does.
    private var soundBinding: Binding<String?> {
        Binding {
            settings[TimerSettings.sound]
        } set: { name in
            settings[TimerSettings.sound] = name
            if let name { preview.play(named: name) } else { preview.stop() }
        }
    }
}

/// Settings ▸ Live Activities, under "Timer".
struct TimerActivityOptions: View {
    let settings: SettingsStore
    var body: some View {
        Toggle(isOn: settings.binding(TimerSettings.peeksAtOneMinute)) { Text(TimerCopy.peekOption) }
    }
}

#Preview("Timer options") {
    let services = CrannyServices.preview()
    VStack(alignment: .leading) {
        TimerOptionsView(settings: services.settings)
        TimerActivityOptions(settings: services.settings).padding(Space.l)
    }
    .frame(width: 320)
}
