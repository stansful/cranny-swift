// CrannySettingsUI/Panes/LiveActivitiesPane.swift — Settings ▸ Live Activities (DESIGN.md §9, §11.1): a draggable priority
// list (one section per class: alerts, ongoing, passive) with a switch per activity and, under it, "Peek on change" and
// the activity's own options from its module (`RegisteredActivity.makeOptions`); then the global behaviour rows. The
// stage above shows the compact state, so toggles and order are visible at once. Reordering has a path for every input
// (ARCHITECTURE §9.5): drag a row onto another of its class (`draggable` / `dropDestination`: a grouped `Form` is not a
// `List` on recent macOS, so `onMove` would never fire), the row's context menu (Move up / Move down), ⌥↑ ⌥↓ on a
// focused row, VoiceOver actions.
import CrannyCore
import Foundation
import SwiftUI

struct LiveActivitiesPane: View {
    let registry: ModuleRegistry
    private var settings: SettingsStore { registry.services.settings }

    var body: some View {
        let groups = ActivityOrdering.groups(registry.activities.map(\.kind), order: settings[CoreSettings.activityOrder])
        SettingsForm(.liveActivities) {
            if groups.isEmpty {
                Section {
                    Text("No live activities are available yet.", bundle: .module, comment: "Settings ▸ Live Activities: no module registered one")
                        .foregroundStyle(.secondary)
                }
            }
            ForEach(groups, id: \.priority) { group in
                Section {
                    ForEach(group.kinds) { kind in
                        ActivityRow(kind: kind, registered: registry.activity(kind.id), settings: settings, groups: groups)
                    }
                } header: {
                    Text(verbatim: Self.title(of: group.priority))
                } footer: {
                    if group.priority == groups.first?.priority {
                        Text("Drag to set which activity wins when two are of the same kind, or use ⌥↑ and ⌥↓.", bundle: .module,
                             comment: "Settings ▸ Live Activities: footer of the priority list (⌥↑ ⌥↓ move the focused activity)")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            ActivityBehaviourSection(settings: settings)
        }
    }

    static func title(of priority: ActivityPriority) -> String {
        switch priority {
        case .hud: String(localized: "HUD", bundle: .module, comment: "Settings: the HUD (volume and brightness overlay) as a name or column header")
        case .alert: String(localized: "Alerts", bundle: .module, comment: "Settings ▸ Live Activities: priority class header (meeting soon, timer done…)")
        case .ongoing: String(localized: "Ongoing", bundle: .module, comment: "Settings ▸ Live Activities: priority class header (now playing, timer…)")
        case .passive: String(localized: "Passive", bundle: .module, comment: "Settings ▸ Live Activities: priority class header (paused media)")
        }
    }
}

/// One activity: icon, name and switch; "Peek on change" and the module's options under it.
private struct ActivityRow: View {
    let kind: ActivityKind
    let registered: RegisteredActivity?
    let settings: SettingsStore
    let groups: [ActivityOrdering.Group]
    /// Another row of this class is dragged over this one.
    @State private var isDropTarget = false

    var body: some View {
        let preferences = settings[CoreSettings.activityPreferences]
        let preference = ActivityOrdering.preference(kind, in: preferences)
        let isDefault = preferences[kind.id] == nil
        let info = ActivitiesRows.row(for: kind)
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: binding(\.isEnabled)) {
                HStack(spacing: 8) {
                    SidebarIcon(symbol: kind.symbol, tint: .pink)
                    RowLabel(title: kind.title, isChanged: !isDefault)
                }
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            if kind.canPeekOnChange || registered?.makeOptions != nil {
                VStack(alignment: .leading, spacing: 6) {
                    if kind.canPeekOnChange {
                        Toggle(isOn: binding(\.peeksOnChange)) {
                            Text("Peek on change", bundle: .module, comment: "Settings ▸ Live Activities: per-activity toggle (glossary: мини-просмотр)")
                        }
                        .toggleStyle(.switch)
                        .controlSize(.small)
                    }
                    if let options = registered?.makeOptions {
                        options()
                            .toggleStyle(.switch)
                            .controlSize(.small)
                    }
                }
                .padding(.leading, 28)
                .disabled(!preference.isEnabled)
            }
        }
        .background {
            RoundedRectangle(cornerRadius: SettingsMetrics.dropTargetRadius, style: .continuous)
                .fill(Color.accentColor.opacity(isDropTarget ? SettingsMetrics.dropTargetOpacity : 0))
                .padding(.horizontal, -6)
                .padding(.vertical, -3)
                .allowsHitTesting(false)
        }
        // Drag: the dropped row takes this row's place (within one class; other drops are refused).
        .draggable(kind.id.rawValue) {
            Label {
                Text(verbatim: kind.title)
            } icon: {
                SidebarIcon(symbol: kind.symbol, tint: .pink)
            }
            .padding(Space.s)
        }
        .dropDestination(for: String.self) { items, _ in
            guard let raw = items.first,
                  let order = ActivityOrdering.dropping(ActivityID(raw), on: kind.id, in: groups) else { return false }
            settings[CoreSettings.activityOrder] = order
            return true
        } isTargeted: { targeted in
            isDropTarget = targeted
        }
        .settingRow(info, isDefault: isDefault) {
            settings[CoreSettings.activityPreferences][kind.id] = nil
        } menu: {
            Button { move(by: -1) } label: { Self.moveUpTitle }
                .disabled(!canMove(by: -1))
            Button { move(by: 1) } label: { Self.moveDownTitle }
                .disabled(!canMove(by: 1))
        }
        // Keyboard: the row is a focus stop while keyboard navigation is on (no ring otherwise); ⌥↑ ⌥↓ reorder it.
        .focusable(interactions: .activate)
        .onKeyPress(keys: [.upArrow, .downArrow]) { press in
            guard press.modifiers.contains(.option) else { return .ignored }
            move(by: press.key == .upArrow ? -1 : 1)
            return .handled
        }
        .accessibilityActions {
            if canMove(by: -1) { Button { move(by: -1) } label: { Self.moveUpTitle } }
            if canMove(by: 1) { Button { move(by: 1) } label: { Self.moveDownTitle } }
        }
    }

    private static var moveUpTitle: Text {
        Text("Move Up", bundle: .module, comment: "Settings ▸ Live Activities: context menu item and VoiceOver action that raises an activity")
    }
    private static var moveDownTitle: Text {
        Text("Move Down", bundle: .module, comment: "Settings ▸ Live Activities: context menu item and VoiceOver action that lowers an activity")
    }

    /// Whether the kind can move one place up (−1) or down (+1) within its class.
    private func canMove(by offset: Int) -> Bool {
        ActivityOrdering.canShift(kind.id, by: offset, in: groups)
    }

    private func move(by offset: Int) {
        guard canMove(by: offset) else { return }
        settings[CoreSettings.activityOrder] = ActivityOrdering.shifting(kind.id, by: offset, in: groups)
    }

    private func binding(_ path: WritableKeyPath<ActivityPreference, Bool>) -> Binding<Bool> {
        Binding(get: { ActivityOrdering.preference(kind, in: settings[CoreSettings.activityPreferences])[keyPath: path] },
                set: { value in
                    let preferences = settings[CoreSettings.activityPreferences]
                    var preference = ActivityOrdering.preference(kind, in: preferences)
                    preference[keyPath: path] = value
                    settings[CoreSettings.activityPreferences] = ActivityOrdering.setting(preference, for: kind, in: preferences)
                })
    }
}

/// The global rows (DESIGN.md §11.1): peek duration, swipe up to dismiss, auto-unhide, quick peek on hover, satellite,
/// inactivity timeout, menu-bar courtesy.
private struct ActivityBehaviourSection: View {
    let settings: SettingsStore

    var body: some View {
        Section {
            SliderRow(ActivitiesRows.peekDuration, settings: settings, key: CoreSettings.peekDuration, range: 1.6...6, step: 0.2,
                      footnote: String(localized: "How long a peek stays before it folds back.", bundle: .module,
                                       comment: "Settings ▸ Live Activities: footnote of Peek duration")) { SettingsFormat.seconds($0) }
            ToggleRow(info: ActivitiesRows.quickPeek, settings: settings, key: CoreSettings.quickPeekOnHover,
                      footnote: String(localized: "Rest the pointer on an activity to see its details.", bundle: .module,
                                       comment: "Settings ▸ Live Activities: footnote of Quick peek on hover"))
            ToggleRow(info: ActivitiesRows.swipeToDismiss, settings: settings, key: CoreSettings.swipeToDismiss,
                      footnote: String(localized: "Hides an activity until its next change: a new song, the last minute, a meeting starting.",
                                       bundle: .module, comment: "Settings ▸ Live Activities: footnote of Swipe up to dismiss"))
            ToggleRow(info: ActivitiesRows.autoUnhide, settings: settings, key: CoreSettings.autoUnhide)
            ToggleRow(info: ActivitiesRows.satellite, settings: settings, key: CoreSettings.satellite,
                      footnote: String(localized: "A second activity appears as a small circle beside the notch.", bundle: .module,
                                       comment: "Settings ▸ Live Activities: footnote of Satellite"))
            ChoiceRow(ActivitiesRows.inactivity, settings: settings, key: CoreSettings.compactInactivityTimeout,
                      choices: [0, 10, 30, 60, 120, 300].map { Choice(value: Double($0), label: SettingsFormat.timeout(Double($0))) },
                      footnote: String(localized: "Folds the activity back into the notch; the satellite stays.", bundle: .module,
                                       comment: "Settings ▸ Live Activities: footnote of Fold away after"), style: .menu)
            ToggleRow(info: ActivitiesRows.menuBarCourtesy, settings: settings, key: CoreSettings.menuBarCourtesy,
                      footnote: String(localized: "Activities beside the notch step aside when the pointer heads for menu bar items next to them.",
                                       bundle: .module, comment: "Settings ▸ Live Activities: footnote of Make way for the menu bar"))
        } header: {
            Text("Behavior", bundle: .module, comment: "Settings ▸ Live Activities: section header of the global rows")
        }
    }
}

#Preview("Live Activities") {
    LiveActivitiesPane(registry: ModuleRegistry(services: .preview()))
        .frame(width: 650, height: 700)
}
