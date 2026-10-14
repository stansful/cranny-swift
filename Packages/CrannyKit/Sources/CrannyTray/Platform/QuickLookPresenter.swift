// CrannyTray/Platform/QuickLookPresenter.swift — Quick Look for tray items from a non-activating panel
// (ARCHITECTURE.md §7.8, decision documented in the WP8 report).
//
// `QLPreviewPanel` needs a controller in the KEY window's responder chain and, like every floating panel of an
// inactive app, does not show while Cranny is inactive. The notch panel is non-activating and usually not key, so:
// remember the frontmost app, activate Cranny (an explicit user action: Space or "Quick Look"), make a tiny invisible
// anchor window key whose content view is the panel's controller, then show the panel. When Quick Look ends, the
// anchor goes away and the previous app is re-activated (macOS 14 cooperative activation).
import AppKit
import CrannyCore
import Foundation
import os
import QuickLookUI

private let log = Log.logger(.tray)

@MainActor final class QuickLookPresenter: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    private let notch: any NotchControl
    private var urls: [URL] = []
    private var anchor: QuickLookAnchorWindow?
    private var previousApp: NSRunningApplication?
    private(set) var isVisible = false

    init(notch: any NotchControl) { self.notch = notch }

    func show(_ urls: [URL], at index: Int) {
        guard !urls.isEmpty, let panel = QLPreviewPanel.shared() else { return }
        self.urls = urls
        let start = min(max(index, 0), urls.count - 1)
        if isVisible, panel.isVisible {
            panel.reloadData()
            panel.currentPreviewItemIndex = start
            return
        }
        let front = NSWorkspace.shared.frontmostApplication
        previousApp = front?.processIdentifier == NSRunningApplication.current.processIdentifier ? nil : front
        let window = anchor ?? QuickLookAnchorWindow(presenter: self)
        anchor = window
        isVisible = true
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(window.contentView)
        panel.makeKeyAndOrderFront(nil)
        panel.currentPreviewItemIndex = start
        log.info("quick look: \(urls.count, privacy: .public) item(s)")
    }

    func close() {
        guard isVisible else { return }
        QLPreviewPanel.shared()?.orderOut(nil)
        finish()
    }

    // MARK: Controller (called by the anchor view)

    func begin(_ panel: QLPreviewPanel) {
        panel.dataSource = self
        panel.delegate = self
        panel.reloadData()
    }

    func end(_ panel: QLPreviewPanel) {
        panel.dataSource = nil
        panel.delegate = nil
        finish()
    }

    private func finish() {
        guard isVisible else { return }
        isVisible = false
        anchor?.orderOut(nil)
        if let previousApp, NSApp.isActive, !previousApp.isTerminated {
            NSApp.yieldActivation(to: previousApp)
            previousApp.activate(from: .current, options: [])
        }
        previousApp = nil
    }

    // MARK: QLPreviewPanelDataSource

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { urls.count }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        urls.indices.contains(index) ? urls[index] as NSURL : nil
    }
}

/// A 1-pt, fully transparent window that only exists to put `QuickLookAnchorView` in the key window's chain.
@MainActor private final class QuickLookAnchorWindow: NSWindow {
    init(presenter: QuickLookPresenter) {
        let screen = NSScreen.main?.frame ?? .zero
        super.init(contentRect: CGRect(x: screen.midX, y: screen.maxY - 2, width: 1, height: 1),
                   styleMask: [.borderless], backing: .buffered, defer: true)
        isReleasedWhenClosed = false
        alphaValue = 0
        hasShadow = false
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
        isExcludedFromWindowsMenu = true
        contentView = QuickLookAnchorView(presenter: presenter)
    }
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// The Quick Look panel's controller (the `QLPreviewPanelController` informal protocol on `NSResponder`).
@MainActor private final class QuickLookAnchorView: NSView {
    private weak var presenter: QuickLookPresenter?
    init(presenter: QuickLookPresenter) {
        self.presenter = presenter
        super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { nil }
    override var acceptsFirstResponder: Bool { true }
    // QLPreviewPanel calls its controller on the main thread (it is an AppKit panel driven by the responder chain).
    nonisolated override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { true }
    nonisolated override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        MainActor.assumeIsolated { if let shared = QLPreviewPanel.shared() { presenter?.begin(shared) } }
    }
    nonisolated override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        MainActor.assumeIsolated { if let shared = QLPreviewPanel.shared() { presenter?.end(shared) } }
    }
}
