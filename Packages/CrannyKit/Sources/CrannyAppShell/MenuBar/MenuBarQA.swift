// CrannyAppShell/MenuBar/MenuBarQA.swift — DEBUG-only visual QA of the menu bar extra (launch arguments listed in
// QAHooks.swift: --qa-menu, --qa-demo, --qa-update-check, --qa-snapshot). Opens the app's OWN status item menu with
// `performClick` (an in-process action, no synthesized input), so the native menu can be captured by window id or
// rendered in-process with --qa-snapshot (which also works while the displays sleep). A submenu cannot be opened
// by code: its rows (title, ✓, disabled) are written to qa-trace.txt next to the snapshots instead.
// Note: while a status menu tracks, the main queue (Swift tasks, `queue: .main` observers) is not served; only
// common-mode run-loop timers and synchronous notifications run. Compiled out of Release.
#if DEBUG
import AppKit
import CoreGraphics
import CrannyCore
import Foundation
import os

private let log = Log.logger(.app)

@MainActor enum MenuBarQA {
    nonisolated enum Target: String, CaseIterable, Sendable { case main, pause, showOn }

    /// The menu bar's QA launch arguments (listed in QAHooks.swift).
    struct Options: Equatable {
        var menu: Target?
        var demo: Bool?
        var updateCheck = false
        var snapshotDirectory: String?
        var snapshotTimes: [Double] = [3]

        init(menu: Target? = nil, demo: Bool? = nil, updateCheck: Bool = false, snapshotDirectory: String? = nil,
             snapshotTimes: [Double] = [3]) {
            self.menu = menu; self.demo = demo; self.updateCheck = updateCheck
            self.snapshotDirectory = snapshotDirectory; self.snapshotTimes = snapshotTimes
        }

        init(arguments: [String]) {
            func value(_ name: String) -> String? {
                guard let i = arguments.firstIndex(of: name), i + 1 < arguments.count else { return nil }
                return arguments[i + 1]
            }
            self.init(menu: value("--qa-menu").flatMap(Target.init(rawValue:)),
                      demo: value("--qa-demo").flatMap { ["on": true, "off": false][$0] },
                      updateCheck: arguments.contains("--qa-update-check"),
                      snapshotDirectory: value("--qa-snapshot"),
                      snapshotTimes: value("--qa-snapshot-at").map { $0.split(separator: ",").compactMap { Double($0) } } ?? [3])
        }

        var isEmpty: Bool { menu == nil && demo == nil && !updateCheck && snapshotDirectory == nil }
    }

    static func apply(_ options: Options, to appControl: any AppControl) {
        guard !options.isEmpty else { return }
        traceURL = options.snapshotDirectory.map { URL(filePath: $0, directoryHint: .isDirectory).appending(path: "qa-trace.txt") }
        if let directory = options.snapshotDirectory {
            scheduleSnapshots(to: URL(filePath: directory, directoryHint: .isDirectory), at: options.snapshotTimes)
        }
        guard let appControl = appControl as? ShellAppControl else { return }
        if let demo = options.demo {
            Task {
                try? await Task.sleep(for: .seconds(1))
                appControl.demo?.set(demo)
                log.info("QA: demo mode \(demo, privacy: .public)")
            }
        }
        if options.updateCheck {
            Task {
                try? await Task.sleep(for: .seconds(1))
                appControl.checkForUpdatesFromMenu()
            }
            // Close the result alert after a while (nobody clicks during QA), so a menu can follow. A common-mode
            // timer, because Swift tasks wait while the alert runs modally.
            RunLoop.main.add(Timer(timeInterval: 7, repeats: false) { _ in
                MainActor.assumeIsolated { if NSApp.modalWindow != nil { NSApp.abortModal() } }      // main run loop
            }, forMode: .common)
        }
        if let menu = options.menu {
            Task {
                try? await Task.sleep(for: .seconds(options.updateCheck ? 8 : 1.5))
                open(menu)
            }
        }
    }

    /// Opens the menu (or pops one submenu up on its own under the icon, since a submenu cannot be opened by code).
    static func open(_ target: Target) {
        guard let button = statusButton() else { log.error("QA: no status item button"); return }
        log.info("QA: opening menu \(target.rawValue, privacy: .public)")
        trace("open \(target.rawValue): button \(button), menu \(button.menu.map { "\($0.items.count) items" } ?? "nil")")
        guard target != .main else { button.performClick(nil); return }
        let title = target == .pause
            ? String(localized: "Pause Live Activities", bundle: .module, comment: "Menu bar: submenu that silences live activities and peeks for a while")
            : String(localized: "Show On", bundle: .module, comment: "Menu bar: submenu listing the displays that show Cranny")
        // Delivered synchronously on the main thread (`queue: nil`): the main queue is not served while the menu tracks.
        trackingObserver = NotificationCenter.default.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil,
                                                                  queue: nil) { note in
            nonisolated(unsafe) let tracked = note.object as? NSMenu
            MainActor.assumeIsolated {                                                   // posted on the main thread
                trace("tracking began: \(tracked.map { "\($0.items.map(\.title)) super \($0.supermenu != nil)" } ?? "nil")")
                guard let menu = tracked, menu.supermenu == nil else { return }
                if let observer = trackingObserver { NotificationCenter.default.removeObserver(observer) }
                trackingObserver = nil
                // SwiftUI fills the items after tracking begins; look again a moment later (timers run while tracking).
                nonisolated(unsafe) let root = menu
                RunLoop.main.add(Timer(timeInterval: 0.3, repeats: false) { _ in
                    MainActor.assumeIsolated { popUpSubmenu(titled: title, of: root, under: button) }   // main run loop
                }, forMode: .common)
            }
        }
        button.performClick(nil)
    }

    private static var trackingObserver: (any NSObjectProtocol)?

    private static func popUpSubmenu(titled title: String, of menu: NSMenu, under button: NSStatusBarButton) {
        trace("items: \(menu.items.map(\.title))")
        guard let submenu = menu.items.first(where: { $0.title == title })?.submenu else {
            log.error("QA: no submenu \(title, privacy: .public)")
            return
        }
        menu.cancelTracking()
        // A menu that still hangs off its parent item does not pop up on its own: show a copy (same items and actions).
        guard let copy = submenu.copy() as? NSMenu else { return }
        trace("submenu: \(copy.items.map { "\($0.title)\($0.state == .on ? " ✓" : "")\($0.isEnabled ? "" : " (disabled)")" })")
        let anchor = button.window.map { CGPoint(x: $0.frame.minX, y: $0.frame.minY - 4) } ?? .zero
        nonisolated(unsafe) let popped = copy
        RunLoop.main.add(Timer(timeInterval: 0.1, repeats: false) { _ in
            MainActor.assumeIsolated {                                                                 // main run loop
                let shown = popped.popUp(positioning: nil, at: anchor, in: nil)
                trace("popUp returned \(shown)")
            }
        }, forMode: .common)
    }

    private static var traceURL: URL?

    /// Appends a line to `qa-trace.txt` in the snapshot directory (what the QA run saw, for the person reading it).
    private static func trace(_ line: String) {
        guard let traceURL else { return }
        let old = (try? String(contentsOf: traceURL, encoding: .utf8)) ?? ""
        try? (old + line + "\n").write(to: traceURL, atomically: true, encoding: .utf8)
    }

    /// Renders every visible window of the app into PNGs at those seconds after launch. In-process drawing
    /// (`cacheDisplay`), so it works while the displays sleep and needs no screen-recording permission.
    /// Window-server materials (menu and alert backgrounds) are not part of the drawing.
    static func scheduleSnapshots(to directory: URL, at times: [Double]) {
        for time in times {
            // A run-loop timer in the common modes also fires while a menu is tracking (Swift tasks wait until it ends).
            let timer = Timer(timeInterval: time, repeats: false) { _ in
                MainActor.assumeIsolated { snapshot(to: directory, label: String(format: "%05.1f", time)) }   // main run loop
            }
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    private static func snapshot(to directory: URL, label: String) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let numbers = Set(NSApp.windows.map(\.windowNumber))
        // Menus and alerts may not be listed in `NSApp.windows`; ask the window server for this process's windows too.
        let extra = ((CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]]) ?? [])
            .filter { ($0[kCGWindowOwnerPID as String] as? Int32) == ProcessInfo.processInfo.processIdentifier }
            .compactMap { ($0[kCGWindowNumber as String] as? Int).flatMap { numbers.contains($0) ? nil : NSApp.window(withWindowNumber: $0) } }
        for window in NSApp.windows + extra where window.isVisible {
            guard let view = window.contentView?.superview ?? window.contentView, view.bounds.width >= 1, view.bounds.height >= 1,
                  let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
            view.cacheDisplay(in: view.bounds, to: rep)
            let name = "\(label)-L\(window.level.rawValue)-\(window.windowNumber)-\(type(of: window)).png"
            do { try rep.representation(using: .png, properties: [:])?.write(to: directory.appending(path: name)) } catch {
                log.error("QA: snapshot not written: \(error.localizedDescription, privacy: .public)")
            }
        }
        log.info("QA: snapshot \(label, privacy: .public)")
    }

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
