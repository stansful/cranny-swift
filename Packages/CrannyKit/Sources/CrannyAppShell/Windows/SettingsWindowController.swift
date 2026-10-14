// CrannyAppShell/Windows/SettingsWindowController.swift — the Settings window (ARCHITECTURE.md §5.9, D11; DESIGN.md §11.1), WP14.
// An AppKit-managed NSWindow hosting `SettingsRootView`, so any pane (or row: "general#hoverDelay") can be opened
// programmatically from an agent app (no SwiftUI `Settings` scene). 860 × 620 by default, 780 × 560 minimum; the frame
// is autosaved and the last pane is restored. SwiftUI drives the toolbar and title (`sceneBridgingOptions`), so the
// sidebar and toolbar get the system's Liquid Glass on macOS 26+ and Cranny adds none of its own.
import AppKit
import CrannyCore
import CrannySettingsUI
import SwiftUI

@MainActor final class SettingsWindowController: NSObject, NSWindowDelegate {
    /// Not a Cranny setting (Reset All keeps it): the pane shown last, restored when Settings opens without one.
    private static let lastPaneKey = "CrannySettingsLastPane"

    private let registry: ModuleRegistry
    private let defaults: UserDefaults
    private var window: NSWindow?
    private var host: NSHostingController<AnyView>?
    /// The pane on screen (reported by the root view).
    private var currentPage: SettingsPageID?
    /// The app that was frontmost before Settings opened gets activation back on close.
    private var previousApp: NSRunningApplication?
    /// Bumped on every rebuild, so a new initial page (or the same pane with another row) resets the root's state.
    private var rootSerial = 0

    init(registry: ModuleRegistry, defaults: UserDefaults = .standard) {
        self.registry = registry
        self.defaults = defaults
    }

    /// Opens (or brings forward) Settings, showing `page` if given ("pane" or "pane#row"); nil restores the last pane.
    /// Call in response to a user action (cooperative activation, DESIGN.md §11.1).
    func show(page: SettingsPageID?) {
        let front = NSWorkspace.shared.frontmostApplication
        if front?.processIdentifier != ProcessInfo.processInfo.processIdentifier { previousApp = front }
        if let window, let host {
            // Rebuild only to go somewhere else; an open window keeps its search and scroll state otherwise.
            if let page, page != currentPage || page.rawValue.contains("#") { host.rootView = root(page) }
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
            return
        }
        let host = NSHostingController(rootView: root(page ?? lastPage))
        host.sizingOptions = []
        host.sceneBridgingOptions = [.title, .toolbars]
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 860, height: 620),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.contentViewController = host
        window.contentMinSize = CGSize(width: 780, height: 560)
        window.setContentSize(CGSize(width: 860, height: 620))
        window.isReleasedWhenClosed = false
        window.toolbarStyle = .unified
        window.titlebarSeparatorStyle = .automatic
        window.tabbingMode = .disallowed
        window.collectionBehavior.insert(.fullScreenNone)
        window.delegate = self
        window.center()
        window.setFrameAutosaveName("CrannySettings")
        self.window = window
        self.host = host
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        #if DEBUG
        applyQAAppearance(to: window)
        scheduleQASnapshot()
        #endif
    }

    func windowWillClose(_ notification: Notification) {
        // Cooperative activation hand-back (§5.9, [UNVERIFIED] R1 §3.5).
        if let previousApp, !previousApp.isTerminated { previousApp.activate() }
        previousApp = nil
    }

    #if DEBUG
    /// Visual QA (Debug only): `-CrannyQAAppearance light|dark` pins this window's appearance (Settings otherwise
    /// follows the system, DESIGN.md §11.1).
    private func applyQAAppearance(to window: NSWindow) {
        switch defaults.string(forKey: "CrannyQAAppearance") {
        case "light": window.appearance = NSAppearance(named: .aqua)
        case "dark": window.appearance = NSAppearance(named: .darkAqua)
        default: break
        }
    }

    /// Visual QA (Debug only): `-CrannyQASnapshot <file.png>` renders the window's own view hierarchy to a PNG after
    /// `-CrannyQASnapshotDelay` seconds (default 3). Unlike `screencapture`, it works while the displays sleep.
    private func scheduleQASnapshot() {
        guard let path = defaults.string(forKey: "CrannyQASnapshot") else { return }
        let delay = defaults.double(forKey: "CrannyQASnapshotDelay")
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay > 0 ? delay : 3))
            self?.writeSnapshot(to: URL(fileURLWithPath: path))
        }
    }

    private func writeSnapshot(to url: URL) {
        guard let view = window?.contentView?.superview ?? window?.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
    #endif

    private var lastPage: SettingsPageID? {
        defaults.string(forKey: Self.lastPaneKey).map(SettingsPageID.init(rawValue:))
    }

    private func root(_ page: SettingsPageID?) -> AnyView {
        let view = SettingsRootView(registry: registry, initialPage: page) { [weak self] shown in
            guard let self else { return }
            self.currentPage = shown
            self.defaults.set(shown.rawValue, forKey: Self.lastPaneKey)
        }
        rootSerial += 1
        return AnyView(view.id(rootSerial))
    }
}
