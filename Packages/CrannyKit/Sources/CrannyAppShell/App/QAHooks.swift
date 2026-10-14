// CrannyAppShell/App/QAHooks.swift — DEBUG-only visual QA launch arguments (docs/CONTRIBUTING.md):
//
//   --qa-state closed|compact|peek|open   force that state on the primary panel, held regardless of the pointer
//   --qa-page <page id>                   with `open`: show this page (`nook` = Home, `tray`, `page.<uuid>`)
//   --qa-exit-after <seconds>             quit after that many seconds (screenshots in scripts and CI)
//   --qa-settings <pane id>               also open Settings at that pane (`general`, `about`, …)
//
// Menu bar extra (WP16, parsed by `MenuBarQA.Options`):
//   --qa-menu main|pause|showOn           open the menu bar extra's menu (or one of its submenus) after 1.5 s
//   --qa-demo on|off                      turn Demo mode on or off after 1 s, so the icon badge changes live
//   --qa-update-check                     run "Check for Updates…" as the menu does; the alert closes after 7 s
//   --qa-snapshot <dir> [--qa-snapshot-at 1,3.5]   render every window of the app (menus, alerts, the status
//                                         item) in-process into <dir> at those seconds; works while displays sleep
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
    enum State: String, CaseIterable, Sendable { case closed, compact, peek, open }

    struct Options: Equatable {
        var state: State?
        var page: PageID?
        var exitAfter: Double?
        var settingsPage: SettingsPageID?

        init(state: State? = nil, page: PageID? = nil, exitAfter: Double? = nil, settingsPage: SettingsPageID? = nil) {
            self.state = state; self.page = page; self.exitAfter = exitAfter; self.settingsPage = settingsPage
        }

        init(arguments: [String]) {
            func value(_ name: String) -> String? {
                guard let i = arguments.firstIndex(of: name), i + 1 < arguments.count else { return nil }
                return arguments[i + 1]
            }
            self.init(state: value("--qa-state").flatMap(State.init(rawValue:)),
                      page: value("--qa-page").map(PageID.init(rawValue:)),
                      exitAfter: value("--qa-exit-after").flatMap(Double.init).flatMap { $0 > 0 ? $0 : nil },
                      settingsPage: value("--qa-settings").map(SettingsPageID.init(rawValue:)))
        }

        var isEmpty: Bool { state == nil && exitAfter == nil && settingsPage == nil }
    }

    /// The label of the sample activity used for `compact` and `peek`.
    static var sampleLabel: String { String(localized: "Hi", bundle: .module, comment: "Visual QA (Debug builds only): sample activity label") }

    @MainActor static func apply(_ options: Options, to overlay: OverlayCoordinator, appControl: any AppControl) {
        MenuBarQA.apply(MenuBarQA.Options(arguments: CommandLine.arguments), to: appControl)          // WP16
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
        if let seconds = options.exitAfter {
            Task {
                try? await Task.sleep(for: .seconds(seconds))
                log.info("QA: exiting after \(seconds, privacy: .public) s")
                NSApp.terminate(nil)
            }
        }
    }
}
#endif
