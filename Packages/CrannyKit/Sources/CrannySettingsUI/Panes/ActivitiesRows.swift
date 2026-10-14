// CrannySettingsUI/Panes/ActivitiesRows.swift — the rows of Settings ▸ Live Activities, shared by the pane and search.
import CrannyCore
import Foundation

enum ActivitiesRows {
    /// One row per listed activity kind ("timer" finds the Timer activity).
    static func row(for kind: ActivityKind) -> SettingsRowInfo {
        SettingsRowInfo(.liveActivities, "kind.\(kind.id.rawValue)", title: kind.title)
    }

    static var peekDuration: SettingsRowInfo {
        SettingsRowInfo(.liveActivities, "peekDuration",
                        title: String(localized: "Peek duration", bundle: .module, comment: "Settings ▸ Live Activities: slider (glossary: мини-просмотр)"))
    }
    static var quickPeek: SettingsRowInfo {
        SettingsRowInfo(.liveActivities, "quickPeekOnHover",
                        title: String(localized: "Quick peek on hover", bundle: .module, comment: "Settings ▸ Live Activities: toggle"))
    }
    static var swipeToDismiss: SettingsRowInfo {
        SettingsRowInfo(.liveActivities, "swipeToDismiss",
                        title: String(localized: "Swipe up to dismiss", bundle: .module, comment: "Settings ▸ Live Activities and Gestures: toggle"))
    }
    static var autoUnhide: SettingsRowInfo {
        SettingsRowInfo(.liveActivities, "autoUnhide",
                        title: String(localized: "Show dismissed activities again when they change", bundle: .module,
                                      comment: "Settings ▸ Live Activities: toggle (auto-unhide)"))
    }
    static var satellite: SettingsRowInfo {
        SettingsRowInfo(.liveActivities, "satellite",
                        title: String(localized: "Satellite", bundle: .module, comment: "Settings ▸ Live Activities: toggle (a second activity in a small circle)"))
    }
    static var inactivity: SettingsRowInfo {
        SettingsRowInfo(.liveActivities, "inactivity",
                        title: String(localized: "Fold away after", bundle: .module, comment: "Settings ▸ Live Activities: inactivity timeout of compact activities"))
    }
    static var menuBarCourtesy: SettingsRowInfo {
        SettingsRowInfo(.liveActivities, "menuBarCourtesy",
                        title: String(localized: "Make way for the menu bar", bundle: .module, comment: "Settings ▸ Live Activities: toggle (menu-bar courtesy)"))
    }

    static func all(registry: ModuleRegistry) -> [SettingsRowInfo] {
        ActivityOrdering.listed(registry.activities.map(\.kind)).map(row(for:))
            + [peekDuration, quickPeek, swipeToDismiss, autoUnhide, satellite, inactivity, menuBarCourtesy]
    }
}
