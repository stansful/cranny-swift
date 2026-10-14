// CrannyTray/Platform/QuickLookPresenter.swift — Quick Look for tray items (ARCHITECTURE.md §7.8).
//
// Decision: the shared `QLPreviewPanel` is NOT used. It finds its data source through the KEY window's responder chain
// and, like every floating panel of an inactive app, only shows while its app is active — so from the non-activating
// notch panel it would have to activate Cranny and take focus from the user's app (and with Cranny inactive it came up
// empty: "No items selected", verified on macOS 27). Instead the same Quick Look preview (`QLPreviewView`, every type
// Quick Look supports, with its media controls) is shown in Cranny's own non-activating floating panel: Cranny is never
// activated, Space and Esc close it, ← → step through the items, and closing hands key focus back to the previous
// window (the window server does this when a non-activating panel orders out, R1 §3.5).
import AppKit
import CrannyCore
import Foundation
import os
import QuickLookUI

private let log = Log.logger(.tray)

@MainActor final class QuickLookPresenter {
    private var panel: TrayPreviewPanel?
    private var urls: [URL] = []
    private var index = 0

    var isVisible: Bool { panel?.isVisible == true }

    /// Shows `urls[index]`; if the preview is already up, switches to the new items in place.
    func show(_ urls: [URL], at index: Int) {
        guard !urls.isEmpty else { return }
        self.urls = urls
        self.index = min(max(index, 0), urls.count - 1)
        guard let panel = panel ?? makePanel() else { return }
        self.panel = panel
        display()
        if !panel.isVisible {
            panel.setFrame(Self.frame(for: NSEvent.mouseLocation), display: false)
            panel.makeKeyAndOrderFront(nil)             // key without activating Cranny (.nonactivatingPanel)
        }
        log.info("quick look: \(urls.count, privacy: .public) item(s)")
    }

    func close() {
        panel?.preview.previewItem = nil          // stops a playing movie; the view stays usable (close() would end it)
        panel?.orderOut(nil)
    }

    private func step(_ delta: Int) {
        guard urls.count > 1 else { return }
        index = (index + delta + urls.count) % urls.count
        display()
    }

    private func display() {
        guard let panel, urls.indices.contains(index) else { return }
        panel.preview.previewItem = urls[index] as NSURL
        panel.title = urls[index].lastPathComponent
    }

    private func makePanel() -> TrayPreviewPanel? {
        guard let preview = QLPreviewView(frame: .zero, style: .normal) else { return nil }
        return TrayPreviewPanel(preview: preview) { [weak self] command in
            switch command {
            case .close: self?.close()
            case .previous: self?.step(-1)
            case .next: self?.step(1)
            }
        }
    }

    /// 62 % of the visible frame of the screen under the pointer, centred a little above the middle.
    static func frame(for point: CGPoint) -> CGRect {
        let screen = NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let size = CGSize(width: min(max(visible.width * 0.62, 480), 1100), height: min(max(visible.height * 0.62, 360), 820))
        return CGRect(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2 + visible.height * 0.04,
                      width: size.width, height: size.height).integral
    }
}

/// A floating, non-activating panel hosting a `QLPreviewView`. Space, Esc and ⌘W close it; ← → page through items.
@MainActor final class TrayPreviewPanel: NSPanel {
    enum Command { case close, previous, next }

    let preview: QLPreviewView
    private let handle: @MainActor (Command) -> Void

    init(preview: QLPreviewView, handle: @escaping @MainActor (Command) -> Void) {
        self.preview = preview
        self.handle = handle
        super.init(contentRect: CGRect(x: 0, y: 0, width: 760, height: 540),
                   styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .nonactivatingPanel],
                   backing: .buffered, defer: true)
        isFloatingPanel = true
        level = .floating
        hidesOnDeactivate = false                      // Cranny is never the active app
        becomesKeyOnlyIfNeeded = false
        isReleasedWhenClosed = false
        titlebarAppearsTransparent = true
        collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace]
        animationBehavior = .documentWindow
        preview.shouldCloseWithWindow = false
        preview.autostarts = true
        contentView = preview
    }

    override var canBecomeKey: Bool { true }

    /// Keys are taken before the preview sees them (a playing movie would otherwise keep Space).
    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown {
            let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
            switch (event.keyCode, modifiers) {
            case (49, []), (53, []): return handle(.close)                      // Space, Esc
            case (13, .command): return handle(.close)                          // ⌘W
            case (123, []): return handle(.previous)                            // ←
            case (124, []): return handle(.next)                                // →
            default: break
            }
        }
        super.sendEvent(event)
    }

    override func performClose(_ sender: Any?) { handle(.close) }
}
