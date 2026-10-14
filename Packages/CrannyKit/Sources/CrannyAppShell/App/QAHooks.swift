// CrannyAppShell/App/QAHooks.swift — DEBUG-only visual QA launch arguments (docs/CONTRIBUTING.md):
//
//   --qa-state closed|compact|peek|open   force that state on the primary panel, held regardless of the pointer
//   --qa-page <page id>                   with `open`: show this page (`nook` = Home, `tray`, `page.<uuid>`)
//   --qa-exit-after <seconds>             quit after that many seconds (screenshots in scripts and CI)
//   --qa-settings <pane id>               also open Settings at that pane (`general`, `about`, …)
//   --qa-snapshot <file.png>              render the visible panel's SwiftUI content to a PNG in-process (ImageRenderer
//                                         of the panel's root view: no Screen Recording permission, works while locked;
//                                         AppKit-backed content such as a live camera layer is not included)
//   --qa-snapshot-after <seconds>         when to take it (default 3)
//
// No input is synthesized: the state is written through the same view-model inputs the pointer uses.
// The whole file is compiled out of Release builds.
#if DEBUG
import AppKit
import CrannyCore
import CrannyNotchUI
import Foundation
import os
import SwiftUI

private let log = Log.logger(.app)

enum QAHooks {
    enum State: String, CaseIterable, Sendable { case closed, compact, peek, open }

    struct Options: Equatable {
        var state: State?
        var page: PageID?
        var exitAfter: Double?
        var settingsPage: SettingsPageID?
        var snapshotPath: String?
        var snapshotAfter: Double?

        init(state: State? = nil, page: PageID? = nil, exitAfter: Double? = nil, settingsPage: SettingsPageID? = nil,
             snapshotPath: String? = nil, snapshotAfter: Double? = nil) {
            self.state = state; self.page = page; self.exitAfter = exitAfter; self.settingsPage = settingsPage
            self.snapshotPath = snapshotPath; self.snapshotAfter = snapshotAfter
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
                      snapshotPath: value("--qa-snapshot"),
                      snapshotAfter: value("--qa-snapshot-after").flatMap(Double.init).flatMap { $0 >= 0 ? $0 : nil })
        }

        var isEmpty: Bool { state == nil && exitAfter == nil && settingsPage == nil && snapshotPath == nil }
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
        if let path = options.snapshotPath {
            Task {
                try? await Task.sleep(for: .seconds(options.snapshotAfter ?? 3))
                snapshotPanel(to: URL(fileURLWithPath: path))
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

    /// Renders the visible panel's root view into a PNG (DEBUG visual QA; see `--qa-snapshot`). `cacheDisplay` drops
    /// SwiftUI's layer content (the black shape, text), so the same root view is rendered again with ImageRenderer.
    @MainActor static func snapshotPanel(to url: URL) {
        guard let panel = NSApp.windows.first(where: { $0 is NotchPanel && $0.isVisible }),
              let host = panel.contentView?.subviews.lazy.compactMap({ $0 as? NSHostingView<NotchCanvasView> }).first else {
            log.error("QA: no panel to snapshot"); return
        }
        let renderer = ImageRenderer(content: host.rootView.frame(width: host.bounds.width, height: host.bounds.height))
        renderer.scale = panel.backingScaleFactor
        do {
            guard let image = renderer.cgImage,
                  let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
                throw CocoaError(.fileWriteUnknown)
            }
            try data.write(to: url)
            log.info("QA: panel snapshot written")
        } catch {
            log.error("QA: snapshot failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
#endif
