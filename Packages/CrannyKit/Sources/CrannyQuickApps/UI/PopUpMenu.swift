// CrannyQuickApps/UI/PopUpMenu.swift — a real NSMenu popped up by a left click on a tile (the "+" and "+N"
// tiles). A SwiftUI `Menu` would flatten the tile into a pop-up button; an NSMenu keeps the tile's own look,
// shows app icons and holds the panel open while it tracks (the shell's menu hold, ARCHITECTURE.md §4.5).
import AppKit
import SwiftUI

/// One row of a pop-up menu.
struct MenuEntry {
    enum Kind {
        case action(@MainActor () -> Void)
        case submenu([MenuEntry])
        case disabled
        case separator
    }

    var title: String
    var image: NSImage?
    var kind: Kind

    init(_ title: String, image: NSImage? = nil, action: @escaping @MainActor () -> Void) {
        self.title = title; self.image = image; self.kind = .action(action)
    }
    init(_ title: String, image: NSImage? = nil, submenu: [MenuEntry]) {
        self.title = title; self.image = image; self.kind = .submenu(submenu)
    }
    init(disabled title: String) { self.title = title; self.image = nil; self.kind = .disabled }
    static var separator: MenuEntry { MenuEntry(kind: .separator) }
    private init(kind: Kind) { self.title = ""; self.image = nil; self.kind = kind }
}

@MainActor enum PopUpMenu {
    /// Pops `entries` up where the click happened (in the clicked window), or at the pointer when the button
    /// was pressed from the keyboard. Returns when the menu closed.
    static func show(_ entries: [MenuEntry]) {
        guard !entries.isEmpty else { return }
        let menu = makeMenu(entries)
        if let event = NSApp.currentEvent, event.type == .leftMouseUp || event.type == .leftMouseDown,
           let view = event.window?.contentView {
            menu.popUp(positioning: nil, at: view.convert(event.locationInWindow, from: nil), in: view)
        } else {
            menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        }
    }

    private static func makeMenu(_ entries: [MenuEntry]) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        for entry in entries {
            switch entry.kind {
            case .separator:
                menu.addItem(.separator())
            case .disabled:
                let item = NSMenuItem(title: entry.title, action: nil, keyEquivalent: "")
                item.isEnabled = false
                menu.addItem(item)
            case .action(let handler):
                let target = MenuActionTarget(handler)
                let item = NSMenuItem(title: entry.title, action: #selector(MenuActionTarget.perform(_:)), keyEquivalent: "")
                item.target = target
                item.representedObject = target            // NSMenuItem.target is weak
                item.image = entry.image
                menu.addItem(item)
            case .submenu(let children):
                let item = NSMenuItem(title: entry.title, action: nil, keyEquivalent: "")
                item.image = entry.image
                item.submenu = makeMenu(children)
                menu.addItem(item)
            }
        }
        return menu
    }
}

private final class MenuActionTarget: NSObject {
    private let handler: @MainActor () -> Void
    init(_ handler: @escaping @MainActor () -> Void) { self.handler = handler }
    @objc func perform(_ sender: Any?) { handler() }
}
