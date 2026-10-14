// CrannyAppShell/App/QAHooks.swift — DEBUG-only visual QA launch arguments (docs/CONTRIBUTING.md):
//
//   --qa-state closed|compact|peek|open   force that state on the primary panel, held regardless of the pointer
//              calibrate                  the Appearance ▸ Notch fit outline and loupe
//              keyboard                   open as the hot key does (takes key focus) and log focus facts
//   --qa-page <page id>                   with `open`: show this page (`nook` = Home, `tray`, `page.<uuid>`)
//   --qa-exit-after <seconds>             quit after that many seconds (screenshots in scripts and CI)
//   --qa-settings <pane id>               also open Settings at that pane (`general`, `about`, …)
//   --qa-capture <directory>              write a PNG of each visible window (the panel, Settings) after
//   --qa-capture-after <seconds>          … this many seconds (default 3). Rendered in-process (`cacheDisplay`):
//                                         works where `screencapture` cannot, needs no Screen Recording access
//   --qa-snapshot <file.png>              render the primary panel's canvas offscreen to that PNG (handled by
//                                         CrannyNotchUI's NotchUIQAHooks; no Screen Recording access needed)
//
// Menu bar extra (parsed by `MenuBarQA.Options`):
//   --qa-menu main|pause|showOn           open the menu bar extra's menu (or one of its submenus) after 1.5 s
//   --qa-demo on|off                      turn Demo mode on or off after 1 s, so the icon badge changes live
//   --qa-update-check                     run "Check for Updates…" as the menu does (Settings ▸ About opens)
//   --qa-open-cranny <seconds>            run the menu's "Open Cranny" then (it opens, never closes)
//   --qa-pause oneHour|untilTomorrow|untilResumed|resume   after 1.5 s, pause as that menu item does (resume:
//                                         pause for an hour, then Resume), so the confirmation flash shows
//   --qa-show-tutorial                    run the menu's "Show Tutorial" after 1 s (the menu then has Skip Tutorial)
//   --qa-snapshot <dir> [--qa-snapshot-at 1,3.5]   render every window of the app (menus, Settings, the status
//                                         item) in-process into <dir> at those seconds; works while displays sleep
//
// Welcome and tutorial (acted on by `WelcomeWindowController`):
//   --qa-welcome <step>                   show the Welcome window at a step (`hello`, `openIt`, `gestures`,
//                                         `preset`, `permissions`, `done`); records nothing
//   --qa-tutorial <n>                     start the interactive tutorial at step n (1-based); records nothing
//   --qa-snapshot <dir>                   with --qa-welcome / --qa-tutorial: also draw every visible window into
//                                         <dir>/<level>-<n>.png (+ frames.txt) after 3 s
//
// `--qa-snapshot` is one argument with two meanings: a path ending in `.png` is the panel canvas (NotchUI); any
// other path is a directory for the window snapshots (menu bar extra, welcome).
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
        /// `WelcomeStep` raw value; `WelcomeWindowController` acts on it.
        var welcomeStep: String?
        /// 1-based tutorial step; `WelcomeWindowController` starts the tutorial there.
        var tutorialStep: Int?
        /// `--qa-snapshot`: a `.png` file (the panel canvas, NotchUI) or a directory for in-process window snapshots.
        var snapshotPath: String?

        init(state: State? = nil, page: PageID? = nil, exitAfter: Double? = nil, settingsPage: SettingsPageID? = nil,
             captureDirectory: URL? = nil, captureAfter: Double = 3,
             welcomeStep: String? = nil, tutorialStep: Int? = nil, snapshotPath: String? = nil) {
            self.state = state; self.page = page; self.exitAfter = exitAfter; self.settingsPage = settingsPage
            self.captureDirectory = captureDirectory; self.captureAfter = captureAfter
            self.welcomeStep = welcomeStep; self.tutorialStep = tutorialStep; self.snapshotPath = snapshotPath
        }

        init(arguments: [String]) {
            let parsed = LaunchArguments(arguments)
            func value(_ name: String) -> String? { parsed.value(after: name) }
            self.init(state: value("--qa-state").flatMap(State.init(rawValue:)),
                      page: value("--qa-page").map(PageID.init(rawValue:)),
                      exitAfter: value("--qa-exit-after").flatMap(Double.init).flatMap { $0 > 0 ? $0 : nil },
                      settingsPage: value("--qa-settings").map(SettingsPageID.init(rawValue:)),
                      captureDirectory: value("--qa-capture").map { URL(fileURLWithPath: $0, isDirectory: true) },
                      captureAfter: value("--qa-capture-after").flatMap(Double.init).flatMap { $0 >= 0 ? $0 : nil } ?? 3,
                      welcomeStep: value("--qa-welcome"),
                      tutorialStep: value("--qa-tutorial").flatMap(Int.init).flatMap { $0 > 0 ? $0 : nil },
                      snapshotPath: value("--qa-snapshot"))
        }

        /// A snapshot alone forces nothing (it records what the other arguments show).
        var isEmpty: Bool {
            state == nil && exitAfter == nil && settingsPage == nil && captureDirectory == nil
                && welcomeStep == nil && tutorialStep == nil
        }

        /// `--qa-snapshot <dir>` (not a `.png` file, which is NotchUI's panel snapshot; the rule is
        /// `LaunchArguments.qaSnapshotDirectory`).
        var snapshotDirectory: URL? {
            LaunchArguments(["--qa-snapshot", snapshotPath].compactMap { $0 }).qaSnapshotDirectory
                .map { URL(fileURLWithPath: $0, isDirectory: true) }
        }
    }

    /// The label of the sample activity used for `compact` and `peek`.
    static var sampleLabel: String { String(localized: "Hi", bundle: .module, comment: "Visual QA (Debug builds only): sample activity label") }

    @MainActor static func apply(_ options: Options, to overlay: OverlayCoordinator, appControl: any AppControl) {
        MenuBarQA.apply(MenuBarQA.Options(arguments: CommandLine.arguments), to: appControl)
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
