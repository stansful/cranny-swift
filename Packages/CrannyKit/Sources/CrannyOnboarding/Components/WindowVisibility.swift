// CrannyOnboarding/Components/WindowVisibility.swift — what the Welcome window's content needs to know about
// its window: whether it is actually visible (not occluded, not minimised), so the stage's light pauses when
// nobody can see it (DESIGN.md §4.7), and when it closes, so nothing outside the window (the coach mark, the
// notch observer) outlives it. Event-driven: window notifications, no polling.
import AppKit
import SwiftUI

struct WindowObserver: NSViewRepresentable {
    @Binding var isVisible: Bool
    let onClose: @MainActor () -> Void

    func makeNSView(context: Context) -> ObserverView {
        let view = ObserverView()
        update(view)
        return view
    }

    func updateNSView(_ view: ObserverView, context: Context) { update(view) }

    private func update(_ view: ObserverView) {
        let binding = $isVisible
        view.onVisibility = { visible in if binding.wrappedValue != visible { binding.wrappedValue = visible } }
        view.onClose = onClose
    }

    final class ObserverView: NSView {
        var onVisibility: @MainActor (Bool) -> Void = { _ in }
        var onClose: @MainActor () -> Void = {}
        private var observers: [any NSObjectProtocol] = []

        /// Also called with `window == nil` when the view leaves its window: the observers go with it.
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            for observer in observers { NotificationCenter.default.removeObserver(observer) }
            observers.removeAll()
            guard let window else { return }
            let center = NotificationCenter.default
            observers.append(center.addObserver(forName: NSWindow.didChangeOcclusionStateNotification, object: window,
                                                queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.reportVisibility() }                 // queue: .main
            })
            observers.append(center.addObserver(forName: NSWindow.willCloseNotification, object: window,
                                                queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.onClose() }                          // queue: .main
            })
            Task { [weak self] in self?.reportVisibility() }          // not during SwiftUI's view update
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        private func reportVisibility() {
            onVisibility(window?.occlusionState.contains(.visible) ?? false)
        }
    }
}
