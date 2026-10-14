// CrannyTodos/UI/TodoWindowAnchor.swift — the window a SwiftUI view is in, read when an action needs it (for
// `TodoUndo.undoManager(hostedIn:fallback:)`). Not observed: reading it never re-renders anything.
import AppKit
import SwiftUI

@MainActor final class TodoWindowAnchor {
    fileprivate weak var view: NSView?
    /// nil until the view is in a window, or when it is not hosted in one (menu items).
    var window: NSWindow? { view?.window }
}

/// An empty, zero-size AppKit view placed in a `.background` that tells its `TodoWindowAnchor` where it lives.
struct TodoWindowAnchorView: NSViewRepresentable {
    let anchor: TodoWindowAnchor

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.setAccessibilityElement(false)
        anchor.view = view
        return view
    }

    func updateNSView(_ view: NSView, context: Context) { anchor.view = view }
}
