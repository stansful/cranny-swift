import AppKit
import CrannyCore
import Foundation
import SwiftUI
import Testing
@testable import CrannyTodos

/// The list's keyboard map and clicks inside the real widget: events are dispatched to an offscreen window that is
/// never ordered in (`NSWindow.sendEvent`, in process; nothing reaches the system's event stream).
@MainActor
struct TodoListKeyboardTests {
    let services = CrannyServices.preview()

    private func host(_ model: TodosModel) -> (NSWindow, NSView) {
        let theme = CrannyTheme()
        let grid = theme.grid
        let view = TodosView(model: model, context: WidgetContext(
            cells: 3, contentSize: CGSize(width: grid.width(cells: 3) - 24, height: grid.height - 24), isFocused: true))
            .crannyCard(cells: 3)
            .crannyThemeRoot(theme)
        let host = NSHostingView(rootView: view)
        host.frame = CGRect(origin: .zero, size: host.fittingSize)
        let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = host
        return (window, host)
    }

    private func settle(_ host: NSView) async throws {
        for _ in 0..<3 {
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(60))
        }
    }

    private enum Key {
        case down, up, space, returnKey, delete
        var code: UInt16 { switch self { case .down: 125; case .up: 126; case .space: 49; case .returnKey: 36; case .delete: 51 } }
        var characters: String {
            switch self {
            case .down: "\u{F701}"
            case .up: "\u{F700}"
            case .space: " "
            case .returnKey: "\r"
            case .delete: "\u{7F}"
            }
        }
    }

    private func press(_ key: Key, command: Bool = false, in window: NSWindow, host: NSView) async throws {
        let flags: NSEvent.ModifierFlags = command ? [.command] : []
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            let event = try #require(NSEvent.keyEvent(with: type, location: .zero, modifierFlags: flags, timestamp: 0,
                                                       windowNumber: window.windowNumber, context: nil,
                                                       characters: key.characters, charactersIgnoringModifiers: key.characters,
                                                       isARepeat: false, keyCode: key.code))
            window.sendEvent(event)
        }
        try await settle(host)
    }

    @Test func arrowsSpaceAndCommandArrowsDriveTheList() async throws {
        let model = TodosModel.preview([Todo(title: "a"), Todo(title: "b"), Todo(title: "c")], services: services)
        services.settings[TodosSettings.hidesCompleted] = false
        let (window, host) = host(model)
        try await settle(host)                                   // the widget has the keyboard: row "a" is selected
        try await press(.down, in: window, host: host)           // → "b"
        try await press(.space, in: window, host: host)          // check "b"
        #expect(model.items.map(\.isDone) == [false, true, false])
        try await press(.down, command: true, in: window, host: host)   // move "b" below "c"
        #expect(model.items.map(\.title) == ["a", "c", "b"])
        try await press(.returnKey, in: window, host: host)      // edit "b"
        #expect(model.editingID == model.items[2].id)
        window.contentView = nil
    }

    /// A click at `point` (top-left coordinates of the card) through the window, like the panel receives it.
    private func click(_ point: CGPoint, in window: NSWindow, host: NSView) async throws {
        let location = CGPoint(x: point.x, y: host.bounds.height - point.y)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = try #require(NSEvent.mouseEvent(with: type, location: location, modifierFlags: [], timestamp: 0,
                                                         windowNumber: window.windowNumber, context: nil,
                                                         eventNumber: 0, clickCount: 1, pressure: 1))
            window.sendEvent(event)
        }
        try await settle(host)
    }

    @Test func clickingTheCircleChecksAndClickingTheTitleEdits() async throws {
        let model = TodosModel.preview([Todo(title: "a"), Todo(title: "b")], services: services)
        services.settings[TodosSettings.hidesCompleted] = false
        let (window, host) = host(model)
        // SwiftUI hit-tests only windows on the window list: put it there, far outside every screen (invisible).
        window.setFrameOrigin(CGPoint(x: -20_000, y: -20_000))
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }
        try await settle(host)
        // Card padding 12, header 16 + 4: the first row spans y 32…54, its circle x 12…28.
        let row = CGFloat(12 + 16 + 4) + TodoMetrics(textSize: .standard).rowHeight / 2
        try await click(CGPoint(x: 20, y: row), in: window, host: host)
        #expect(model.items[0].isDone)
        try await click(CGPoint(x: 80, y: row + 22), in: window, host: host)
        #expect(model.editingID == model.items[1].id)
        #expect(window.firstResponder is NSTextView)
        window.contentView = nil
    }

    @Test func returnOnNewToDoStartsADraftAndCommandDeleteRemovesARow() async throws {
        let model = TodosModel.preview([Todo(title: "a")], services: services)
        let (window, host) = host(model)
        try await settle(host)
        try await press(.delete, command: true, in: window, host: host)  // ⌘⌫ on "a"
        #expect(model.items.isEmpty)
        // The list is empty now, so the empty state has the keyboard: ↩ starts a to-do.
        try await press(.returnKey, in: window, host: host)
        #expect(model.items.count == 1 && model.editingID == model.items.first?.id)
        window.contentView = nil
    }
}
