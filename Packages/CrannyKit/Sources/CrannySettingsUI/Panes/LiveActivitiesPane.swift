// CrannySettingsUI/Panes/LiveActivitiesPane.swift — Settings ▸ Live Activities (DESIGN.md §9, §11.1): a draggable priority
// list (one section per class: alerts, ongoing, passive) with a switch per activity and, under it, "Peek on change" and
// the activity's own options from its module (`RegisteredActivity.makeOptions`); then the global behaviour rows. The
// stage above shows the compact state, so toggles and order are visible at once.
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
                    .onMove { source, destination in
                        settings[CoreSettings.activityOrder] = ActivityOrdering.moving(in: groups, priority: group.priority,
                                                                                       from: source, to: destination)
                    }
                } header: {
                    Text(verbatim: Self.title(of: group.priority))
                } footer: {
                    if group.priority == groups.first?.priority {
                        Text("Drag to set which activity wins when two are of the same kind.", bundle: .module,
                             comment: "Settings ▸ Live Activities: footer of the priority list")
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
        .settingRow(info, isDefault: isDefault) {
            settings[CoreSettings.activityPreferences][kind.id] = nil
        }
        .accessibilityAction(named: Text("Move up", bundle: .module, comment: "Settings ▸ Live Activities: VoiceOver action that raises an activity")) {
            settings[CoreSettings.activityOrder] = ActivityOrdering.shifting(kind.id, by: -1, in: groups)
        }
        .accessibilityAction(named: Text("Move down", bundle: .module, comment: "Settings ▸ Live Activities: VoiceOver action that lowers an activity")) {
            settings[CoreSettings.activityOrder] = ActivityOrdering.shifting(kind.id, by: 1, in: groups)
        }
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
                      footnote: String(localized: "The wings step aside when the pointer heads for menu bar items next to them.", bundle: .module,
                                       comment: "Settings ▸ Live Activities: footnote of Make way for the menu bar"))
        } header: {
            Text("Behaviour", bundle: .module, comment: "Settings ▸ Live Activities: section header of the global rows")
        }
    }
}

#Preview("Live Activities") {
    LiveActivitiesPane(registry: ModuleRegistry(services: .preview()))
        .frame(width: 650, height: 700)
}
