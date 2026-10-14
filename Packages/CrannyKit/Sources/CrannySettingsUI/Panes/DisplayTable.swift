// CrannySettingsUI/Panes/DisplayTable.swift — General ▸ Show on + the per-display table (DESIGN.md §3.7, §11.1):
// built-in / pointer / all / chosen displays, and for each connected display its style (Automatic, Floating island,
// Attached, Off) and whether it shows live activities, peeks and the HUD. Rows are keyed by
// `ThemeResolver.displayKey` (stable across reconnects) and named with `NSScreen.localizedName`.
import AppKit
import CrannyCore
import CrannyNotchUI
import Foundation
import SwiftUI

/// "Show on" as a flat choice (the custom list is edited in the table).
enum DisplayMode: Hashable, CaseIterable {
    case builtIn, pointer, all, custom

    init(_ selection: DisplaySelection) {
        switch selection {
        case .builtIn: self = .builtIn
        case .pointer: self = .pointer
        case .all: self = .all
        case .custom: self = .custom
        }
    }

    /// The selection for this mode; switching to the custom list starts from the displays shown now.
    func selection(current: DisplaySelection, shown: [DisplayKey]) -> DisplaySelection {
        switch self {
        case .builtIn: .builtIn
        case .pointer: .pointer
        case .all: .all
        case .custom:
            if case .custom = current { current } else { .custom(shown) }
        }
    }
}

/// One connected display.
struct ConnectedDisplay: Identifiable {
    let key: DisplayKey
    let name: String
    let hasNotch: Bool
    let isBuiltIn: Bool
    var id: DisplayKey { key }

    @MainActor static func current() -> [ConnectedDisplay] {
        NSScreen.screens.compactMap { screen in
            guard let key = ThemeResolver.displayKey(screen) else { return nil }
            let number = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
            return ConnectedDisplay(key: key, name: screen.localizedName, hasNotch: screen.safeAreaInsets.top > 0,
                                    isBuiltIn: CGDisplayIsBuiltin(number) != 0)
        }
    }
}

struct DisplaySection: View {
    let settings: SettingsStore
    @State private var displays = ConnectedDisplay.current()

    var body: some View {
        let selection = settings[CoreSettings.displaySelection]
        Section {
            ChoiceRow(info: GeneralRows.showOn,
                      selection: Binding(get: { DisplayMode(selection) },
                                         set: { settings[CoreSettings.displaySelection] = $0.selection(current: selection, shown: displays.map(\.key)) }),
                      choices: [
                        Choice(value: .builtIn, label: String(localized: "Built-in display", bundle: .module, comment: "Settings ▸ General ▸ Show on: option")),
                        Choice(value: .pointer, label: String(localized: "Display with the pointer", bundle: .module, comment: "Settings ▸ General ▸ Show on: option")),
                        Choice(value: .all, label: String(localized: "All displays", bundle: .module, comment: "Settings ▸ General ▸ Show on: option")),
                        Choice(value: .custom, label: String(localized: "Chosen displays", bundle: .module, comment: "Settings ▸ General ▸ Show on: option (a custom list)")),
                      ],
                      footnote: String(localized: "Peeks and alerts appear only on the display with the pointer.", bundle: .module,
                                       comment: "Settings ▸ General: footnote of Show on"),
                      style: .menu, isDefault: settings.isDefault(CoreSettings.displaySelection),
                      reset: { settings.reset(CoreSettings.displaySelection) })
            DisplayGrid(settings: settings, displays: displays, selection: selection)
                .settingRow(GeneralRows.displays, isDefault: settings.isDefault(CoreSettings.perDisplay)) {
                    settings.reset(CoreSettings.perDisplay)
                }
        } header: {
            Text(verbatim: GeneralRows.displays.title)
        }
        .task {
            for await _ in NotificationCenter.default.notifications(named: NSApplication.didChangeScreenParametersNotification) {
                displays = ConnectedDisplay.current()
            }
        }
    }
}

/// The table: one row per connected display.
private struct DisplayGrid: View {
    let settings: SettingsStore
    let displays: [ConnectedDisplay]
    let selection: DisplaySelection

    var body: some View {
        let isCustom: Bool = if case .custom = selection { true } else { false }
        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
            GridRow {
                if isCustom { Color.clear.gridCellUnsizedAxes([.horizontal, .vertical]) }
                header(String(localized: "Display", bundle: .module, comment: "Settings ▸ General ▸ Displays: column header"))
                header(String(localized: "Style", bundle: .module, comment: "Settings ▸ General ▸ Displays: column header"))
                header(Self.activitiesTitle).gridColumnAlignment(.center)
                header(Self.peeksTitle).gridColumnAlignment(.center)
                header(Self.hudTitle).gridColumnAlignment(.center)
            }
            Divider().gridCellUnsizedAxes(.horizontal)
            ForEach(displays) { display in
                DisplayRow(settings: settings, display: display, selection: selection, isCustom: isCustom)
            }
        }
        .padding(.vertical, 2)
    }

    private func header(_ text: String) -> some View {
        Text(verbatim: text).font(.caption).foregroundStyle(.secondary)
    }

    static var activitiesTitle: String { String(localized: "Activities", bundle: .module, comment: "Settings ▸ General ▸ Displays: column header (live activities)") }
    static var peeksTitle: String { String(localized: "Peeks", bundle: .module, comment: "Settings ▸ General ▸ Displays: column header") }
    static var hudTitle: String { String(localized: "HUD", bundle: .module, comment: "Settings: the HUD (volume and brightness overlay) as a name or column header") }
}

private struct DisplayRow: View {
    let settings: SettingsStore
    let display: ConnectedDisplay
    let selection: DisplaySelection
    let isCustom: Bool

    var body: some View {
        GridRow {
            if isCustom {
                Toggle(isOn: chosen) { Text(verbatim: display.name) }
                    .labelsHidden()
                    .accessibilityLabel(Text("Show on \(display.name)", bundle: .module,
                                             comment: "Settings ▸ General ▸ Displays: VoiceOver label of the custom-list checkbox; the argument is a display name"))
            }
            HStack(spacing: 6) {
                Image(systemName: display.isBuiltIn ? "laptopcomputer" : "display").foregroundStyle(.secondary).accessibilityHidden(true)
                Text(verbatim: display.name).lineLimit(1)
            }
            Picker(selection: preference(\.style)) {
                Text("Automatic", bundle: .module, comment: "Settings: option chosen automatically (a display style, the accent)").tag(NoNotchStyle?.none)
                if !display.hasNotch {
                    Text("Floating island", bundle: .module, comment: "Settings: no-notch style").tag(NoNotchStyle?.some(.floatingIsland))
                    Text("Attached", bundle: .module, comment: "Settings: no-notch style").tag(NoNotchStyle?.some(.attached))
                }
                Text("Off", bundle: .module, comment: "Settings: option that turns something off (a timeout, a display)").tag(NoNotchStyle?.some(.off))
            } label: {
                Text("Style of \(display.name)", bundle: .module, comment: "Settings ▸ General ▸ Displays: VoiceOver label; the argument is a display name")
            }
            .labelsHidden()
            .fixedSize()
            checkbox(\.showsActivities, DisplayGrid.activitiesTitle)
            checkbox(\.showsPeeks, DisplayGrid.peeksTitle)
            checkbox(\.showsHUD, DisplayGrid.hudTitle)
        }
    }

    private func checkbox(_ path: WritableKeyPath<DisplayPreferences, Bool>, _ title: String) -> some View {
        Toggle(isOn: preference(path)) { Text(verbatim: title) }
            .labelsHidden()
            .toggleStyle(.checkbox)
            .accessibilityLabel(Text(verbatim: "\(title), \(display.name)"))
    }

    /// A binding into this display's preferences; writing the defaults removes the entry.
    private func preference<V>(_ path: WritableKeyPath<DisplayPreferences, V>) -> Binding<V> {
        Binding(get: { (settings[CoreSettings.perDisplay][display.key] ?? DisplayPreferences())[keyPath: path] },
                set: { value in
                    var all = settings[CoreSettings.perDisplay]
                    var entry = all[display.key] ?? DisplayPreferences()
                    entry[keyPath: path] = value
                    all[display.key] = entry == DisplayPreferences() ? nil : entry
                    settings[CoreSettings.perDisplay] = all
                })
    }

    /// Membership of the custom list.
    private var chosen: Binding<Bool> {
        Binding(get: {
            if case .custom(let keys) = selection { keys.contains(display.key) } else { false }
        }, set: { isOn in
            guard case .custom(var keys) = selection else { return }
            keys.removeAll { $0 == display.key }
            if isOn { keys.append(display.key) }
            settings[CoreSettings.displaySelection] = .custom(keys)
        })
    }
}

#Preview("Displays") {
    Form { DisplaySection(settings: CrannyServices.preview().settings) }
        .formStyle(.grouped)
        .frame(width: 650, height: 300)
}
