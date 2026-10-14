// CrannyAppShell/Overlay/NotchPanel.swift — R1 §3.1 configuration (verified on macOS 27).
import AppKit
import SwiftUI

extension NSWindow.Level {
    /// Above the menu bar (24) and status items (25); below menus (101), tooltips (200), drag images (500).
    static let notchOverlay = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
}

final class NotchPanel: NSPanel {
    /// Every scroll event delivered to this window passes through here first (gestures, scroll zones).
    var scrollInterceptor: ((NSEvent) -> Bool)?
    /// Esc (`cancelOperation`) that nothing in the panel handled, e.g. from a text field without its own Esc action
    /// (KeyboardRouter lets field editors see Esc first).
    var onCancel: (() -> Void)?

    init(frame: CGRect) {
        // .nonactivatingPanel MUST be in the init style mask (R1 gotcha 4).
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true            // resets level to 3 -> set level AFTER (R1 gotcha 1)
        level = .notchOverlay
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        isMovable = false
        animationBehavior = .none
        isReleasedWhenClosed = false
        becomesKeyOnlyIfNeeded = true
        isExcludedFromWindowsMenu = true
        acceptsMouseMovedEvents = true
        appearance = NSAppearance(named: .darkAqua)
        // NEVER assign ignoresMouseEvents (tri-state; R1 §4.1).
    }
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
    override func cancelOperation(_ sender: Any?) {
        if let onCancel { onCancel() } else { super.cancelOperation(sender) }
    }
    override func sendEvent(_ event: NSEvent) {
        if event.type == .scrollWheel, let intercept = scrollInterceptor, intercept(event) { return }
        super.sendEvent(event)
    }
}

/// Receives the drops `NotchRootView` gets (AppKit owns drag and drop, §5.6; `DropRouter` implements it).
@MainActor protocol NotchDropTarget: AnyObject {
    func dragUpdated(_ info: any NSDraggingInfo, in view: NSView) -> NSDragOperation
    func dragExited()
    func performDrop(_ info: any NSDraggingInfo, in view: NSView) -> Bool
}

/// Root content view: hit-testing limited to the shape, AppKit drop destination for the Tray.
final class NotchRootView: NSView {
    var interactiveRect: () -> CGRect = { .zero }
    weak var dropTarget: (any NotchDropTarget)?

    /// File URLs, URLs and every file-promise type (Photos, Mail, Safari images; R1 §5.1).
    static let draggedTypes: [NSPasteboard.PasteboardType] =
        [.fileURL, .URL] + NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) }

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes(Self.draggedTypes)
    }
    required init?(coder: NSCoder) { nil }
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard interactiveRect().contains(convert(point, from: superview)) else { return nil }
        return super.hitTest(point)
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // MARK: NSDraggingDestination (forwarded; the root view is the panel's only drop destination)

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        dropTarget?.dragUpdated(sender, in: self) ?? []
    }
    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        dropTarget?.dragUpdated(sender, in: self) ?? []
    }
    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        dropTarget?.dragExited()
    }
    override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool { dropTarget != nil }
    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        dropTarget?.performDrop(sender, in: self) ?? false
    }
    override func wantsPeriodicDraggingUpdates() -> Bool { false }        // updates come with pointer moves only
}

final class NotchHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }   // R1 gotcha 6
}
