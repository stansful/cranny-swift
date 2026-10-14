// CrannySettingsUI/Stage/WindowVisibilityReader.swift — reports whether the window hosting the stage is actually on
// screen (`NSWindow.occlusionState`), so the stage drops its live notch while Settings is covered, minimised or
// closed: SwiftUI keeps views "appeared" in an occluded window, and the light layer's clock would keep running
// (energy rules, ARCHITECTURE §9.2). Event-driven: one notification observer per window, no polling.
import AppKit
import SwiftUI

struct WindowVisibilityReader: NSViewRepresentable {
    let onChange: @MainActor (Bool) -> Void

    func makeNSView(context: Context) -> VisibilityView {
        let view = VisibilityView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ view: VisibilityView, context: Context) { view.onChange = onChange }

    final class VisibilityView: NSView {
        var onChange: @MainActor (Bool) -> Void = { _ in }
        private var observer: (any NSObjectProtocol)?
        private var lastReported: Bool?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let observer { NotificationCenter.default.removeObserver(observer) }
            observer = nil
            guard let window else { report(false); return }
            // Posted on the main thread (AppKit window notification, `queue: .main`).
            observer = NotificationCenter.default.addObserver(forName: NSWindow.didChangeOcclusionStateNotification,
                                                              object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.reportCurrent() }
            }
            reportCurrent()
        }

        private func reportCurrent() { report(window?.occlusionState.contains(.visible) ?? false) }

        private func report(_ visible: Bool) {
            guard visible != lastReported else { return }
            lastReported = visible
            onChange(visible)
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
