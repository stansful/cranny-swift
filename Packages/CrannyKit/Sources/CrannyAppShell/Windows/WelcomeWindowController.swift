// CrannyAppShell/Windows/WelcomeWindowController.swift — the Welcome window (ARCHITECTURE.md §5.9), WP15.
// 640 × 480, full-size content, hidden title bar, not resizable, centred, hosting `WelcomeView`.
// Shown on first launch (`onboardingCompletedVersion == nil`, WP15) and from "Show welcome".
import AppKit
import CrannyCore
import CrannyOnboarding
import SwiftUI

@MainActor final class WelcomeWindowController: NSObject, NSWindowDelegate {
    private let registry: ModuleRegistry
    private var window: NSWindow?

    init(registry: ModuleRegistry) { self.registry = registry }

    func show() {
        if let window {
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
            return
        }
        let view = WelcomeView(registry: registry) { [weak self] in self?.window?.close() }
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 640, height: 480),
                              styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        window.contentViewController = NSHostingController(rootView: view)
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        self.window = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) { window = nil }
}
