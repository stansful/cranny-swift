// CrannySettingsUI/Panes/GeneralRows.swift — the rows of Settings ▸ General (DESIGN.md §11.1), shared by the pane
// (labels) and the search index (labels + localized keywords).
import CrannyCore
import Foundation

enum GeneralRows {
    static var launchAtLogin: SettingsRowInfo {
        SettingsRowInfo(.general, "launchAtLogin",
                        title: String(localized: "Launch at login", bundle: .module, comment: "Settings ▸ General: toggle"),
                        keywords: [String(localized: "startup", bundle: .module, comment: "Settings search: keyword for Launch at login")])
    }
    static var showOn: SettingsRowInfo {
        SettingsRowInfo(.general, "showOn",
                        title: String(localized: "Show on", bundle: .module, comment: "Settings ▸ General: which displays show Cranny"),
                        keywords: [String(localized: "external monitor", bundle: .module, comment: "Settings search: keyword for the display settings"),
                                   String(localized: "display", bundle: .module, comment: "Settings search: keyword for the display settings"),
                                   String(localized: "screen", bundle: .module, comment: "Settings search: keyword for the display settings")])
    }
    static var displays: SettingsRowInfo {
        SettingsRowInfo(.general, "displays",
                        title: String(localized: "Displays", bundle: .module, comment: "Settings ▸ General: per-display table (style, activities, peeks, HUD)"),
                        keywords: [String(localized: "island", bundle: .module, comment: "Settings search: keyword for the per-display style")])
    }
    static var openMode: SettingsRowInfo {
        SettingsRowInfo(.general, "openMode",
                        title: String(localized: "Open Cranny with", bundle: .module, comment: "Settings ▸ General: picker Hover / Click / Shortcut only"))
    }
    static var hoverDelay: SettingsRowInfo {
        SettingsRowInfo(.general, "hoverDelay",
                        title: String(localized: "Hover delay", bundle: .module, comment: "Settings ▸ General: how long the pointer rests before Cranny opens"),
                        keywords: [String(localized: "dwell", bundle: .module, comment: "Settings search: keyword for Hover delay")])
    }
    static var holdOption: SettingsRowInfo {
        SettingsRowInfo(.general, "holdOptionToPass",
                        title: String(localized: "Hold ⌥ to pass over", bundle: .module, comment: "Settings ▸ General: toggle"),
                        keywords: [String(localized: "option", bundle: .module, comment: "Settings search: keyword for Hold ⌥ to pass over")])
    }
    static var closeOnLeave: SettingsRowInfo {
        SettingsRowInfo(.general, "closeOnLeave",
                        title: String(localized: "Close when the pointer leaves", bundle: .module, comment: "Settings ▸ General: toggle"))
    }
    static var inactivityTimeout: SettingsRowInfo {
        SettingsRowInfo(.general, "inactivityTimeout",
                        title: String(localized: "Close after inactivity", bundle: .module, comment: "Settings ▸ General: timeout of the open panel"))
    }
    static var hideWhenIdle: SettingsRowInfo {
        SettingsRowInfo(.general, "hideWhenIdle",
                        title: String(localized: "Hide the handle when idle", bundle: .module, comment: "Settings ▸ General: toggle for displays without a notch"),
                        keywords: [String(localized: "handle", bundle: .module, comment: "Settings search: keyword for the no-notch handle")])
    }
    static var fullScreen: SettingsRowInfo {
        SettingsRowInfo(.general, "fullScreen",
                        title: String(localized: "In full-screen apps", bundle: .module, comment: "Settings ▸ General: picker Hide / Alerts and HUD only / Show"),
                        keywords: [String(localized: "video", bundle: .module, comment: "Settings search: keyword for the full-screen policy")])
    }
    static var excludedApps: SettingsRowInfo {
        SettingsRowInfo(.general, "excludedApps",
                        title: String(localized: "Excluded apps", bundle: .module, comment: "Settings ▸ General: apps in front of which Cranny behaves as in full screen"))
    }
    static var demoMode: SettingsRowInfo {
        SettingsRowInfo(.general, "demoMode",
                        title: String(localized: "Demo mode", bundle: .module, comment: "Settings ▸ General: toggle (glossary: Демо-режим)"),
                        keywords: [String(localized: "screen sharing", bundle: .module, comment: "Settings search: keyword for Demo mode"),
                                   String(localized: "presentation", bundle: .module, comment: "Settings search: keyword for Demo mode")])
    }
    static var redactCalendar: SettingsRowInfo {
        SettingsRowInfo(.general, "demoRedactsCalendar",
                        title: String(localized: "Hide calendar titles", bundle: .module, comment: "Settings ▸ General: Demo mode option"))
    }
    static var uiSounds: SettingsRowInfo {
        SettingsRowInfo(.general, "uiSounds",
                        title: String(localized: "UI sounds", bundle: .module, comment: "Settings ▸ General: toggle"))
    }
    static var menuBarIcon: SettingsRowInfo {
        SettingsRowInfo(.general, "menuBarIcon",
                        title: String(localized: "Show menu bar icon", bundle: .module, comment: "Settings ▸ General: toggle"))
    }
    static var checkForUpdates: SettingsRowInfo {
        SettingsRowInfo(.general, "checksForUpdates",
                        title: String(localized: "Check for updates daily", bundle: .module, comment: "Settings ▸ General: toggle"),
                        keywords: [String(localized: "version", bundle: .module, comment: "Settings search: keyword for updates")])
    }
    static var prereleases: SettingsRowInfo {
        SettingsRowInfo(.general, "includesPrereleases",
                        title: String(localized: "Include pre-releases", bundle: .module, comment: "Settings ▸ General: toggle"))
    }
    static var resetAll: SettingsRowInfo {
        SettingsRowInfo(.general, "resetAll",
                        title: String(localized: "Reset All Settings…", bundle: .module, comment: "Settings ▸ General: destructive button"),
                        keywords: [String(localized: "defaults", bundle: .module, comment: "Settings search: keyword for Reset All Settings")])
    }

    static var all: [SettingsRowInfo] {
        [launchAtLogin, showOn, displays, openMode, hoverDelay, holdOption, closeOnLeave, inactivityTimeout, hideWhenIdle,
         fullScreen, excludedApps, demoMode, redactCalendar, uiSounds, menuBarIcon, checkForUpdates, prereleases, resetAll]
    }
}
