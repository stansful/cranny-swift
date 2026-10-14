// CrannyAppShell/Windows/SettingsWindowController.swift — the Settings window (ARCHITECTURE.md §5.9, D11), WP14.
// An AppKit-managed NSWindow hosting `SettingsRootView`, so any pane can be opened programmatically from
// an agent app (no SwiftUI `Settings` scene). 860 × 620 default, 780 × 560 minimum, frame autosaved.
import AppKit
import CrannyCore
import CrannySettingsUI
import SwiftUI

@MainActor final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let registry: ModuleRegistry
    private var window: NSWindow?
    private var host: NSHostingController<AnyView>?
    /// The app that was frontmost before Settings opened gets activation back on close.
    private var previousApp: NSRunningApplication?

    init(registry: ModuleRegistry) { self.registry = registry }

    /// Opens (or brings forward) Settings, showing `page` if given. Call in response to a user action.
    func show(page: SettingsPageID?) {
        let front = NSWorkspace.shared.frontmostApplication
        if front?.processIdentifier != ProcessInfo.processInfo.processIdentifier { previousApp = front }
        if let window, let host {
            if let page { host.rootView = root(page) }
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
            return
        }
        let host = NSHostingController(rootView: root(page))
        host.sizingOptions = []
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 860, height: 620),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.contentViewController = host
        window.contentMinSize = CGSize(width: 780, height: 560)
        window.setContentSize(CGSize(width: 860, height: 620))
        window.isReleasedWhenClosed = false
        window.titlebarAppearsTransparent = false
        window.toolbarStyle = .unified
        window.delegate = self
        window.center()
        window.setFrameAutosaveName("CrannySettings")
        self.window = window
        self.host = host
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        // Cooperative activation hand-back (§5.9, UNVERIFIED R1 §3.5): WP14 confirms on hardware.
        if let previousApp, !previousApp.isTerminated { previousApp.activate() }
        previousApp = nil
    }

    private func root(_ page: SettingsPageID?) -> AnyView {
        AnyView(SettingsRootView(registry: registry, initialPage: page).id(page?.rawValue ?? "root"))
    }
}
