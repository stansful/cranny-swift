import AppKit
import CrannyCore
import Foundation
import SwiftUI
import Testing
@testable import CrannyTodos

/// Where a deletion's Undo lands. Widget options live in a popover (the card's ⋯ menu, Settings' widget options),
/// whose own undo manager disappears when it closes; ⌘Z is pressed in the window below it afterwards.
/// Windows sit far outside every screen and nothing reaches the system's event stream.
@MainActor
struct TodoUndoTests {
    private func offscreenWindow() -> NSWindow {
        let window = NSWindow(contentRect: CGRect(x: -20_000, y: -20_000, width: 240, height: 160), styleMask: .borderless,
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        return window
    }

    @Test func childWindowsUseTheirTopLevelWindowsUndoManager() throws {
        let fallback = UndoManager()
        #expect(TodoUndo.undoManager(hostedIn: nil, fallback: fallback) === fallback)     // e.g. menu items
        let (panel, child, grandchild) = (offscreenWindow(), offscreenWindow(), offscreenWindow())
        #expect(TodoUndo.undoManager(hostedIn: panel, fallback: fallback) === panel.undoManager)
        panel.addChildWindow(child, ordered: .above)
        child.addChildWindow(grandchild, ordered: .above)
        defer { child.removeChildWindow(grandchild); panel.removeChildWindow(child) }
        #expect(panel.undoManager !== child.undoManager)
        #expect(TodoUndo.undoManager(hostedIn: grandchild, fallback: fallback) === panel.undoManager)
    }

    /// The options in a real popover over a window: "Delete completed" is undone with that window's ⌘Z.
    /// (The button itself is not clicked: a system button ignores the first click in a window that is not key,
    /// and a test process never becomes the active app.)
    @Test func deleteCompletedInAPopoverIsUndoneInTheWindowBelow() async throws {
        let model = TodosModel.testing([Todo(title: "a", isDone: true), Todo(title: "b"), Todo(title: "c", isDone: true)])
        let panel = offscreenWindow()
        let content = NSView(frame: CGRect(x: 0, y: 0, width: 240, height: 160))
        let anchorView = NSView(frame: CGRect(x: 100, y: 20, width: 20, height: 20))
        content.addSubview(anchorView)
        panel.contentView = content
        panel.orderFrontRegardless()                             // a popover needs its window on the window list
        defer { panel.orderOut(nil) }
        let anchor = TodoWindowAnchor()
        let options = NSHostingController(rootView: TodosOptions(model: model)
            .background(TodoWindowAnchorView(anchor: anchor))     // the same anchor the options carry inside
            .padding(Space.l).crannyThemeRoot(CrannyTheme()))
        let popover = NSPopover()
        popover.animates = false
        popover.contentViewController = options
        popover.show(relativeTo: anchorView.bounds, of: anchorView, preferredEdge: .maxY)
        defer { popover.close() }
        try await Task.sleep(for: .milliseconds(200))
        let popoverWindow = try #require(options.view.window)
        #expect(anchor.window === popoverWindow)
        #expect(popoverWindow.parent === panel)
        let undo = try #require(panel.undoManager)
        undo.groupsByEvent = false

        undo.beginUndoGrouping()
        TodoUndo.deleteCompleted(model, hostedIn: anchor.window, fallback: popoverWindow.undoManager)
        undo.endUndoGrouping()
        #expect(model.items.map(\.title) == ["b"])
        #expect(popoverWindow.undoManager?.canUndo != true)      // not on the popover's own, short-lived manager
        #expect(undo.canUndo && undo.undoActionName == TodosStrings.deleteCompleted)
        popover.close()                                          // ⌘Z after the options have closed
        undo.undo()
        #expect(model.items.map(\.title) == ["a", "b", "c"])
        #expect(model.items.map(\.isDone) == [true, false, true])
        undo.redo()
        #expect(model.items.map(\.title) == ["b"])
    }
}
