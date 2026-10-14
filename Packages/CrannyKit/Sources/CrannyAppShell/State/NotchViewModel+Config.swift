// CrannyAppShell/State/NotchViewModel+Config.swift — what the view model reads for each input: the machine's config
// (settings, the lineup, per-display toggles) and the registry/page lookups. Split from `NotchViewModel.swift`.
import AppKit
import CrannyCore
import CrannyNotchUI
import Foundation

extension NotchViewModel {
    // MARK: Lookups

    func activity(_ id: ActivityID) -> (any LiveActivity)? {
        scene.sampleActivities[id] ?? registry.activity(id)?.activity
    }

    /// A grid page from `CoreSettings.pages` or a page a registered module contributes.
    func pageExists(_ page: PageID) -> Bool {
        registry.services.settings[CoreSettings.pages].contains { $0.id == page } || registry.pages.contains { $0.id == page }
    }

    /// A page of `CoreSettings.pages` (not a page a module contributes, such as the Tray).
    func isGridPage(_ page: PageID) -> Bool {
        registry.services.settings[CoreSettings.pages].contains { $0.id == page }
    }

    /// The grid page that holds a widget (clicking an activity opens its widget there).
    func page(containing widget: WidgetID) -> PageID? {
        registry.services.settings[CoreSettings.pages].first { $0.items.contains { $0.widget == widget } }?.id
    }

    /// Whether the grid page `page` shows `widget`.
    func page(_ page: PageID, holds widget: WidgetID) -> Bool {
        registry.services.settings[CoreSettings.pages].contains { $0.id == page && $0.items.contains { $0.widget == widget } }
    }

    func currentConfig() -> NotchMachineConfig {
        let settings = registry.services.settings
        let preferences = scene.context.display.flatMap { settings[CoreSettings.perDisplay][$0] } ?? DisplayPreferences()
        let lastPage = settings[CoreSettings.lastPage]
        let widget = lineup.primary.flatMap { activity($0)?.opensWidget }
        var c = NotchMachineConfig()
        c.openMode = settings[CoreSettings.openMode]
        c.hoverDelay = settings[CoreSettings.hoverDelay].seconds
        c.closeOnLeave = settings[CoreSettings.closeOnLeave]
        c.quickPeekOnHover = settings[CoreSettings.quickPeekOnHover] && preferences.showsPeeks
        c.lastPage = pageExists(lastPage) ? lastPage : settings[CoreSettings.pages].first?.id ?? .nook
        c.voiceOverRunning = NSWorkspace.shared.isVoiceOverEnabled
        c.primary = lineup.primary
        c.satellite = lineup.satellite
        c.primaryWidget = widget
        c.primaryWidgetPage = widget.flatMap(page(containing:))
        c.openInactivityTimeout = settings[CoreSettings.openInactivityTimeout]
        c.compactInactivityTimeout = settings[CoreSettings.compactInactivityTimeout]
        c.hasHandle = !scene.layout.metrics.hasNotch
        c.hidesIdleHandle = settings[CoreSettings.hideHandleWhenIdle]
        c.handleIdleDelay = settings[CoreSettings.handleIdleDelay]
        c.swipeOpenClose = settings[CoreSettings.swipeOpenClose]
        c.swipeToDismiss = settings[CoreSettings.swipeToDismiss]
        c.trackSwipe = settings[CoreSettings.trackSwipe]
        c.acceptsFileDrags = registry.services.tray != nil
        c.menuBarCourtesy = settings[CoreSettings.menuBarCourtesy]
        // The HUD answers a key press Cranny consumed (CrannyHUD): nothing may hide it, neither the menu-bar
        // courtesy nor the compact inactivity timeout, or the user would see no HUD at all.
        if let primary = lineup.primary, activity(primary)?.priority == .hud {
            c.menuBarCourtesy = false
            c.compactInactivityTimeout = 0
        }
        return c
    }

    /// Sum of the visible widget widths on a grid page (module pages use the Home page's width).
    func openColumns(for page: PageID) -> Int {
        let pages = registry.services.settings[CoreSettings.pages]
        guard let grid = pages.first(where: { $0.id == page }) ?? pages.first else { return 10 }
        let cells = grid.items.reduce(0) { sum, item in
            sum + (registry.widget(item.widget)?.sizes.clamp(item.cells) ?? max(item.cells, 1))
        }
        return max(cells, 1)
    }
}
