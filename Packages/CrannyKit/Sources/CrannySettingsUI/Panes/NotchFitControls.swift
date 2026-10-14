// CrannySettingsUI/Panes/NotchFitControls.swift — Appearance ▸ Notch fit (DESIGN.md §3.1): width ±10 pt in 0.5-pt steps
// and bottom radius ±3 pt, stored per display MODEL (`CoreSettings.notchFit`, key `ThemeResolver.displayModelKey`).
// While a slider is dragged the real notch freezes in hover and draws its 1-px outline (`notch.setCalibrationOverlay`);
// crossing 0 plays an `.alignment` detent. Only displays with a notch can be fitted.
import AppKit
import CrannyCore
import CrannyNotchUI
import Foundation
import SwiftUI

/// A connected display with a camera housing, and the model key its fit is stored under.
struct NotchedDisplay: Identifiable, Hashable {
    let model: String
    let name: String
    var id: String { model }

    @MainActor static func current() -> [NotchedDisplay] {
        var seen = Set<String>()
        return NSScreen.screens.compactMap { screen in
            guard screen.safeAreaInsets.top > 0, let model = ThemeResolver.displayModelKey(screen), seen.insert(model).inserted else { return nil }
            return NotchedDisplay(model: model, name: screen.localizedName)
        }
    }
}

struct NotchFitControls: View {
    let settings: SettingsStore
    let notch: any NotchControl
    let haptics: Haptics
    @State private var displays = NotchedDisplay.current()
    @State private var chosen: String?

    var body: some View {
        let model = chosen ?? displays.first?.model
        Section {
            if displays.count > 1 {
                Picker(selection: Binding(get: { model ?? "" }, set: { chosen = $0 })) {
                    ForEach(displays) { Text(verbatim: $0.name).tag($0.model) }
                } label: {
                    Text("Display", bundle: .module, comment: "Settings ▸ General ▸ Displays: column header")
                }
            }
            slider(AppearanceRows.notchFitWidth, model: model, path: \.widthTune, range: -10...10, step: 0.5)
            slider(AppearanceRows.notchFitRadius, model: model, path: \.radiusTune, range: -3...3, step: 0.5)
        } header: {
            Text("Notch fit", bundle: .module, comment: "Settings ▸ Appearance: section header")
        } footer: {
            Text(verbatim: model == nil
                 ? String(localized: "Connect a display with a notch to fit Cranny to its camera housing.", bundle: .module,
                          comment: "Settings ▸ Appearance ▸ Notch fit: footer when no notched display is connected")
                 : String(localized: "While you drag, the notch shows its outline so you can line it up with the camera housing. Saved for this display model.",
                          bundle: .module, comment: "Settings ▸ Appearance ▸ Notch fit: footer"))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .disabled(model == nil)
        .task {
            for await _ in NotificationCenter.default.notifications(named: NSApplication.didChangeScreenParametersNotification) {
                displays = NotchedDisplay.current()
            }
        }
    }

    private func slider(_ info: SettingsRowInfo, model: String?, path: WritableKeyPath<NotchFit, CGFloat>,
                        range: ClosedRange<Double>, step: Double) -> some View {
        let value = Binding<Double>(
            get: { Double(model.flatMap { settings[CoreSettings.notchFit][$0] }?[keyPath: path] ?? 0) },
            set: { newValue in
                guard let model else { return }
                var all = settings[CoreSettings.notchFit]
                var fit = all[model] ?? NotchFit()
                let old = Double(fit[keyPath: path])
                fit[keyPath: path] = CGFloat(newValue)
                all[model] = fit == NotchFit() ? nil : fit
                settings[CoreSettings.notchFit] = all
                if Self.crossesZero(from: old, to: newValue) { haptics.play(.alignment) }
            })
        return SliderRow(info: info, value: value, range: range, step: step, format: { SettingsFormat.points($0) },
                         isDefault: value.wrappedValue == 0, reset: { value.wrappedValue = 0 },
                         onEditingChanged: { notch.setCalibrationOverlay($0) })
    }

    /// The `.alignment` detent at 0 (DESIGN.md §14.2): landing on 0 or passing through it. Leaving 0 is silent in
    /// both directions, so dragging around 0 plays one detent per arrival, the same on each side.
    static func crossesZero(from old: Double, to new: Double) -> Bool {
        old != new && (new == 0 || (old < 0 && new > 0) || (old > 0 && new < 0))
    }
}

#Preview("Notch fit") {
    let services = CrannyServices.preview()
    Form { NotchFitControls(settings: services.settings, notch: services.notch, haptics: services.haptics) }
        .formStyle(.grouped)
        .frame(width: 650, height: 220)
}
