// CrannySettingsUI/Sidebar/KnownPaneKeywords.swift — search terms for the well-known module panes (DESIGN.md §11.1,
// §11.3: "volume" → HUD, "dock" → Quick Apps). A module pane is an opaque view that lists its own `keywords`;
// these aliases make the examples of the design work even before a module lists them. They apply only to panes
// that are registered.
import CrannyCore
import Foundation

enum KnownPaneKeywords {
    static var all: [SettingsPageID: [String]] {
        [
            .hud: [
                String(localized: "volume", bundle: .module, comment: "Settings search: keyword that finds the HUD pane"),
                String(localized: "brightness", bundle: .module, comment: "Settings search: keyword that finds the HUD pane"),
                String(localized: "keyboard backlight", bundle: .module, comment: "Settings search: keyword that finds the HUD pane"),
                String(localized: "sound", bundle: .module, comment: "Settings search: keyword that finds the HUD pane"),
            ],
            .media: [
                String(localized: "music", bundle: .module, comment: "Settings search: keyword that finds the Media pane"),
                String(localized: "now playing", bundle: .module, comment: "Settings search: keyword that finds the Media pane"),
                String(localized: "visualizer", bundle: .module, comment: "Settings search: keyword that finds the Media pane"),
            ],
            .calendar: [
                String(localized: "meeting", bundle: .module, comment: "Settings search: keyword that finds the Calendar pane"),
                String(localized: "events", bundle: .module, comment: "Settings search: keyword that finds the Calendar pane"),
            ],
            .shortcuts: [
                String(localized: "dock", bundle: .module, comment: "Settings search: keyword that finds the Shortcuts pane (Quick Apps)"),
                String(localized: "quick apps", bundle: .module, comment: "Settings search: keyword that finds the Shortcuts pane"),
                String(localized: "launcher", bundle: .module, comment: "Settings search: keyword that finds the Shortcuts pane (Quick Apps)"),
            ],
            .tray: [
                String(localized: "files", bundle: .module, comment: "Settings search: keyword that finds the Tray pane"),
                String(localized: "airdrop", bundle: .module, comment: "Settings search: keyword that finds the Tray pane"),
                String(localized: "pipelines", bundle: .module, comment: "Settings search: keyword that finds the Tray pane"),
            ],
        ]
    }
}
