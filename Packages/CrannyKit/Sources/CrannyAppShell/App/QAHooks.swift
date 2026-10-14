// CrannyAppShell/App/QAHooks.swift — DEBUG-only visual QA launch arguments (docs/CONTRIBUTING.md):
//
//   --qa-state closed|compact|peek|open   force that state on the primary panel, held regardless of the pointer
//              calibrate                  the Appearance ▸ Notch fit outline and loupe (WP13)
//              keyboard                   open as the hot key does (takes key focus) and log focus facts (WP13)
//   --qa-page <page id>                   with `open`: show this page (`nook` = Home, `tray`, `page.<uuid>`)
//   --qa-exit-after <seconds>             quit after that many seconds (screenshots in scripts and CI)
//   --qa-settings <pane id>               also open Settings at that pane (`general`, `about`, …)
//   --qa-capture <directory>              write a PNG of each visible window (the panel, Settings) after
//   --qa-capture-after <seconds>          … this many seconds (default 3). Rendered in-process (`cacheDisplay`):
//                                         works where `screencapture` cannot, needs no Screen Recording access
//   --qa-snapshot <file.png>              render the primary panel's canvas offscreen to that PNG (handled by
//                                         CrannyNotchUI's NotchUIQAHooks; no Screen Recording access needed)
//
// No input is synthesized: the state is written through the same view-model inputs the pointer uses.
// The whole file is compiled out of Release builds.
#if DEBUG
import AppKit
import CrannyCore
import Foundation
import os

private let log = Log.logger(.app)

enum QAHooks {
    enum State: String, CaseIterable, Sendable { case closed, compact, peek, open, calibrate, keyboard }

    struct Options: Equatable {
        var state: State?
        var page: PageID?
        var exitAfter: Double?
        var settingsPage: SettingsPageID?
        var captureDirectory: URL?
        var captureAfter: Double = 3

        init(state: State? = nil, page: PageID? = nil, exitAfter: Double? = nil, settingsPage: SettingsPageID? = nil,
             captureDirectory: URL? = nil, captureAfter: Double = 3) {
            self.state = state; self.page = page; self.exitAfter = exitAfter; self.settingsPage = settingsPage
            self.captureDirectory = captureDirectory; self.captureAfter = captureAfter
        }

        init(arguments: [String]) {
            func value(_ name: String) -> String? {
                guard let i = arguments.firstIndex(of: name), i + 1 < arguments.count else { return nil }
                return arguments[i + 1]
            }
            self.init(state: value("--qa-state").flatMap(State.init(rawValue:)),
                      page: value("--qa-page").map(PageID.init(rawValue:)),
                      exitAfter: value("--qa-exit-after").flatMap(Double.init).flatMap { $0 > 0 ? $0 : nil },
                      settingsPage: value("--qa-settings").map(SettingsPageID.init(rawValue:)),
                      captureDirectory: value("--qa-capture").map { URL(fileURLWithPath: $0, isDirectory: true) },
                      captureAfter: value("--qa-capture-after").flatMap(Double.init).flatMap { $0 >= 0 ? $0 : nil } ?? 3)
        }

        var isEmpty: Bool { state == nil && exitAfter == nil && settingsPage == nil && captureDirectory == nil }
    }

    /// The label of the sample activity used for `compact` and `peek`.
    static var sampleLabel: String { String(localized: "Hi", bundle: .module, comment: "Visual QA (Debug builds only): sample activity label") }

    @MainActor static func apply(_ options: Options, to overlay: OverlayCoordinator, appControl: any AppControl) {
        guard !options.isEmpty else { return }
        if let page = options.settingsPage { appControl.openSettings(page) }
        if let state = options.state {
            log.info("QA: forcing \(state.rawValue, privacy: .public) (page \(options.page?.rawValue ?? "-", privacy: .public))")
            // Let the panel appear first, so the state animates in like it does for a user.
            Task {
                try? await Task.sleep(for: .milliseconds(300))
                overlay.forceQAState(state, page: options.page)
            }
        }
        if let directory = options.captureDirectory {
            Task {
                try? await Task.sleep(for: .seconds(options.captureAfter))
                capture(into: directory)
            }
        }
        if let seconds = options.exitAfter {
            Task {
                try? await Task.sleep(for: .seconds(seconds))
                log.info("QA: exiting after \(seconds, privacy: .public) s")
                NSApp.terminate(nil)
            }
        }
    }

    /// `--qa-capture`: draws each visible window's content into `panel-<n>.png` / `window-<n>.png`. Layers that
    /// SwiftUI does not draw through `cacheDisplay` (Metal effects) come out empty; the views themselves are exact.
    @MainActor static func capture(into directory: URL) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            log.error("QA: capture folder: \(error.localizedDescription, privacy: .public)")
            return
        }
        for window in NSApp.windows where window.isVisible {
            guard let view = window.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
            view.cacheDisplay(in: view.bounds, to: rep)
            guard let data = rep.representation(using: .png, properties: [:]) else { continue }
            let url = directory.appending(path: "\(window is NotchPanel ? "panel" : "window")-\(window.windowNumber).png")
            do {
                try data.write(to: url)
                log.info("QA: captured \(url.lastPathComponent, privacy: .public)")
            } catch {
                log.error("QA: capture failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
#endif
