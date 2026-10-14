// CrannyAppShell/MenuBar/MenuBarQA.swift — DEBUG-only visual QA of the menu bar extra (QAHooks: --qa-menu,
// --qa-demo, --qa-update-check). Opens the app's OWN status item menu with `performClick` (an in-process
// action, no synthesized input), so the native menu can be captured by window id. Compiled out of Release.
#if DEBUG
import AppKit
import CrannyCore
import Foundation
import os

private let log = Log.logger(.app)

@MainActor enum MenuBarQA {
    nonisolated enum Target: String, CaseIterable, Sendable { case main, pause, showOn }

    static func apply(menu: Target?, demo: Bool?, updateCheck: Bool, to appControl: ShellAppControl) {
        if let demo {
            Task {
                try? await Task.sleep(for: .seconds(1))
                appControl.demo?.set(demo)
                log.info("QA: demo mode \(demo, privacy: .public)")
            }
        }
        if updateCheck {
            Task {
                try? await Task.sleep(for: .seconds(1))
                appControl.checkForUpdatesFromMenu()
            }
            // Close the result alert after a while (nobody clicks during QA), so a menu can follow.
            Task {
                try? await Task.sleep(for: .seconds(6))
                if NSApp.modalWindow != nil { NSApp.abortModal() }
            }
        }
        if let menu {
            Task {
                try? await Task.sleep(for: .seconds(updateCheck ? 8 : 1.5))
                open(menu)
            }
        }
    }

    /// Opens the menu (or pops one submenu up on its own under the icon, since a submenu cannot be opened by code).
    static func open(_ target: Target) {
        guard let button = statusButton() else { log.error("QA: no status item button"); return }
        log.info("QA: opening menu \(target.rawValue, privacy: .public)")
        guard target != .main else { button.performClick(nil); return }
        let title = target == .pause
            ? String(localized: "Pause Live Activities", bundle: .module, comment: "Menu bar: submenu that silences live activities and peeks for a while")
            : String(localized: "Show On", bundle: .module, comment: "Menu bar: submenu listing the displays that show Cranny")
        trackingObserver = NotificationCenter.default.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil,
                                                                  queue: .main) { note in
            // Delivered on the main queue, where the menu lives: handing it to the main actor crosses nothing.
            nonisolated(unsafe) let tracked = note.object as? NSMenu
            MainActor.assumeIsolated {                                                   // queue: .main
                guard let menu = tracked, menu.supermenu == nil else { return }
                if let observer = trackingObserver { NotificationCenter.default.removeObserver(observer) }
                trackingObserver = nil
                guard let submenu = menu.items.first(where: { $0.title == title })?.submenu else {
                    log.error("QA: no submenu \(title, privacy: .public)")
                    return
                }
                menu.cancelTracking()
                let anchor = button.window.map { CGPoint(x: $0.frame.minX, y: $0.frame.minY - 4) } ?? .zero
                DispatchQueue.main.async { submenu.popUp(positioning: nil, at: anchor, in: nil) }
            }
        }
        button.performClick(nil)
    }

    private static var trackingObserver: (any NSObjectProtocol)?

    /// The button of the menu bar extra's status item (SwiftUI's `MenuBarExtra` puts it in an NSStatusBarWindow).
    private static func statusButton() -> NSStatusBarButton? {
        for window in NSApp.windows where window.className.contains("StatusBar") {
            if let button = find(in: window.contentView) { return button }
        }
        return nil
    }

    private static func find(in view: NSView?) -> NSStatusBarButton? {
        guard let view else { return nil }
        if let button = view as? NSStatusBarButton { return button }
        for subview in view.subviews { if let button = find(in: subview) { return button } }
        return nil
    }
}
#endif
