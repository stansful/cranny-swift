// CrannyTray/UI/FileDragSource.swift — the AppKit layer under a tray tile (ARCHITECTURE.md §5.6 "Drag out", R1 §5.3):
// SwiftUI `.onDrag` hands receivers a temporary copy, so tiles start an `NSDraggingSession` with `NSURL` writers and the
// receiver gets the original file. The same view reports clicks (with ⌘/⇧), double-clicks, hover and the context menu,
// because it sits under the tile's visuals and receives the mouse.
import AppKit
import CrannyCore
import SwiftUI
import UniformTypeIdentifiers

/// What a tile's AppKit layer reports back.
struct FileDragHandlers {
    /// The files a drag from this tile carries (the selection if the tile is selected), with their ids.
    var payload: @MainActor () -> [(id: UUID, url: URL)]
    var image: @MainActor () -> NSImage?
    var click: @MainActor (TraySelection.Modifiers) -> Void
    var doubleClick: @MainActor () -> Void
    var hover: @MainActor (Bool) -> Void
    var menu: @MainActor () -> NSMenu?
    var dragBegan: @MainActor () -> Void
    /// `movedOrDeleted` = the receiver took the files away (`.move`, `.delete`).
    var dragEnded: @MainActor (_ ids: [UUID], _ movedOrDeleted: Bool) -> Void
    /// Tray-owned copies may be moved out; the user's own files only copied or linked (never relocated from here).
    var allowsMove: @MainActor () -> Bool
}

struct FileDragSource: NSViewRepresentable {
    var handlers: FileDragHandlers

    func makeNSView(context: Context) -> FileDragSourceView { FileDragSourceView(handlers: handlers) }
    func updateNSView(_ view: FileDragSourceView, context: Context) { view.handlers = handlers }
}

@MainActor final class FileDragSourceView: NSView, NSDraggingSource {
    var handlers: FileDragHandlers
    private var downEvent: NSEvent?
    private var dragging: [UUID] = []
    private var tracking: NSTrackingArea?

    /// Points the pointer must travel before a press becomes a drag (AppKit's own threshold is similar).
    static let dragThreshold: CGFloat = 4

    init(handlers: FileDragHandlers) {
        self.handlers = handlers
        super.init(frame: .zero)
        setAccessibilityElement(false)       // the SwiftUI tile is the accessibility element
    }
    required init?(coder: NSCoder) { nil }

    // The notch panel is non-activating: the first click must work (R1 gotcha 6).
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// One tracking area for the view's life: with `.inVisibleRect` AppKit keeps it in step with the visible rect
    /// itself (the rect is ignored), so the passes during scrolling and the open morph have nothing to rebuild.
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        guard tracking == nil else { return }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area)
        tracking = area
    }
    override func mouseEntered(with event: NSEvent) { handlers.hover(true) }
    override func mouseExited(with event: NSEvent) { handlers.hover(false) }

    override func mouseDown(with event: NSEvent) {
        downEvent = event
        if event.clickCount == 2 { handlers.doubleClick(); downEvent = nil }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let down = downEvent else { return }
        let a = down.locationInWindow, b = event.locationInWindow
        guard hypot(b.x - a.x, b.y - a.y) >= Self.dragThreshold else { return }
        downEvent = nil
        startDrag(with: down)
    }

    override func mouseUp(with event: NSEvent) {
        guard downEvent != nil else { return }
        downEvent = nil
        var modifiers: TraySelection.Modifiers = []
        if event.modifierFlags.contains(.command) { modifiers.insert(.command) }
        if event.modifierFlags.contains(.shift) { modifiers.insert(.shift) }
        handlers.click(modifiers)
    }

    override func menu(for event: NSEvent) -> NSMenu? { handlers.menu() }

    // MARK: Drag out

    private func startDrag(with event: NSEvent) {
        let payload = handlers.payload()
        guard !payload.isEmpty else { return }
        let image = handlers.image() ?? NSWorkspace.shared.icon(for: .item)
        let side = min(bounds.width, bounds.height)
        let items: [NSDraggingItem] = payload.enumerated().map { index, entry in
            let item = NSDraggingItem(pasteboardWriter: entry.url as NSURL)
            let offset = CGFloat(min(index, 3)) * 4          // a small fanned stack for several files
            item.setDraggingFrame(CGRect(x: (bounds.width - side) / 2 + offset, y: (bounds.height - side) / 2 - offset,
                                         width: side, height: side), contents: image)
            return item
        }
        dragging = payload.map(\.id)
        handlers.dragBegan()
        let session = beginDraggingSession(with: items, event: event, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true
        session.draggingFormation = payload.count > 1 ? .stack : .none
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        // Never into Cranny itself: dropping a tray item on the notch would keep it twice.
        guard context == .outsideApplication else { return [] }
        return handlers.allowsMove() ? [.copy, .move, .link, .generic, .delete] : [.copy, .link, .generic]
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        let ids = dragging
        dragging = []
        handlers.dragEnded(ids, operation.contains(.move) || operation.contains(.delete))
    }
}
