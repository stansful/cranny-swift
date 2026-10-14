// CrannyQuickApps/UI/PopUpMenu.swift — a real NSMenu that drops down under a tile (the "+" and "+N" tiles). A
// SwiftUI `Menu` would flatten the tile into a pop-up button; an NSMenu keeps the tile's own look, shows app icons
// and holds the panel open while it tracks (the shell's menu hold, ARCHITECTURE.md §4.5).
//
// The menu is anchored to the tile's own AppKit view (`MenuAnchor`), so it opens in the same place from a click,
// from the keyboard (↩ / Space on the focused tile) and from VoiceOver, never at a pointer that may be elsewhere.
import AppKit
import CrannyCore
import Observation
import SwiftUI

/// One row of a pop-up menu.
struct MenuEntry {
    enum Kind {
        case action(@MainActor () -> Void)
        case submenu([MenuEntry])
        /// Rebuilt when it opens, and again whenever something `content` reads (an `@Observable` list that is
        /// still loading) changes while the menu is up.
        case liveSubmenu(@MainActor () -> [MenuEntry])
        case disabled
        case separator
    }

    var title: String
    var image: NSImage?
    var toolTip: String?
    var kind: Kind

    init(_ title: String, image: NSImage? = nil, toolTip: String? = nil, action: @escaping @MainActor () -> Void) {
        self.title = title; self.image = image; self.toolTip = toolTip; self.kind = .action(action)
    }
    init(_ title: String, image: NSImage? = nil, submenu: [MenuEntry]) {
        self.title = title; self.image = image; self.kind = .submenu(submenu)
    }
    init(_ title: String, image: NSImage? = nil, liveSubmenu content: @escaping @MainActor () -> [MenuEntry]) {
        self.title = title; self.image = image; self.kind = .liveSubmenu(content)
    }
    init(disabled title: String) { self.title = title; self.kind = .disabled }
    static var separator: MenuEntry { MenuEntry(kind: .separator) }
    private init(kind: Kind) { self.title = ""; self.kind = kind }
}

/// Where a tile's pop-up menu opens: the AppKit view behind the tile (`MenuAnchorView`, its bounds are the tile).
@MainActor final class MenuAnchor {
    fileprivate weak var view: NSView?
    init() {}
}

/// Marks the tile's frame for AppKit. Draws nothing and never takes a click, so the tile behaves as before.
struct MenuAnchorView: NSViewRepresentable {
    let anchor: MenuAnchor

    func makeNSView(context: Context) -> AnchorView {
        let view = AnchorView()
        anchor.view = view
        return view
    }

    func updateNSView(_ view: AnchorView, context: Context) { anchor.view = view }

    final class AnchorView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func isAccessibilityElement() -> Bool { false }
    }
}

@MainActor enum PopUpMenu {
    /// Pops `entries` up under the anchor's tile, aligned with its leading edge. Without an anchor on screen it
    /// falls back to the click, then to the pointer. Returns when the menu closed.
    ///
    /// Call it from an event handler (a button action, a key press, a VoiceOver action), not from a `Task`: the
    /// menu runs a nested event loop, and main-actor work (a live submenu's list) only continues meanwhile when
    /// that loop is not itself inside a main-queue job.
    static func show(_ entries: [MenuEntry], anchor: MenuAnchor?) {
        guard !entries.isEmpty else { return }
        let menu = NSMenu()
        menu.autoenablesItems = false
        fill(menu, with: entries)
        if let view = anchor?.view, view.window != nil {
            let gap = Space.xs
            let below = view.isFlipped ? view.bounds.maxY + gap : view.bounds.minY - gap
            menu.popUp(positioning: nil, at: NSPoint(x: view.bounds.minX, y: below), in: view)
        } else if let event = NSApp.currentEvent, event.type == .leftMouseUp || event.type == .leftMouseDown,
                  let view = event.window?.contentView {
            menu.popUp(positioning: nil, at: view.convert(event.locationInWindow, from: nil), in: view)
        } else {
            menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        }
    }

    static func fill(_ menu: NSMenu, with entries: [MenuEntry]) {
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
                item.toolTip = entry.toolTip
                menu.addItem(item)
            case .submenu(let children):
                let item = NSMenuItem(title: entry.title, action: nil, keyEquivalent: "")
                item.image = entry.image
                let submenu = NSMenu()
                submenu.autoenablesItems = false
                fill(submenu, with: children)
                item.submenu = submenu
                menu.addItem(item)
            case .liveSubmenu(let content):
                let item = NSMenuItem(title: entry.title, action: nil, keyEquivalent: "")
                item.image = entry.image
                let submenu = NSMenu()
                submenu.autoenablesItems = false
                let source = LiveSubmenu(menu: submenu, content: content)
                submenu.delegate = source
                item.representedObject = source            // NSMenu.delegate is weak
                source.reload()
                item.submenu = submenu
                menu.addItem(item)
            }
        }
    }
}

private final class MenuActionTarget: NSObject {
    private let handler: @MainActor () -> Void
    init(_ handler: @escaping @MainActor () -> Void) { self.handler = handler }
    @objc func perform(_ sender: Any?) { handler() }
}

/// Keeps a live submenu current: rebuilt when it is about to open, and whenever something its content read changes
/// while the menu is up (observation re-armed on every rebuild). Released with the menu.
@MainActor private final class LiveSubmenu: NSObject, NSMenuDelegate {
    private weak var menu: NSMenu?
    private let content: @MainActor () -> [MenuEntry]

    init(menu: NSMenu, content: @escaping @MainActor () -> [MenuEntry]) {
        self.menu = menu; self.content = content
    }

    func menuNeedsUpdate(_ menu: NSMenu) { reload() }

    func reload() {
        guard let menu else { return }
        let entries = withObservationTracking { content() } onChange: { [weak self] in
            Task { @MainActor in self?.reload() }
        }
        menu.removeAllItems()
        PopUpMenu.fill(menu, with: entries)
    }
}

#Preview("Menu under a tile") {
    // The anchor draws nothing: the menu drops down under the button it is attached to.
    let anchor = MenuAnchor()
    Button { PopUpMenu.show([MenuEntry("Finder") {}, .separator, MenuEntry(disabled: "Loading…")], anchor: anchor) } label: {
        Text(verbatim: "+")
            .frame(width: 56, height: 56)
    }
    .background(MenuAnchorView(anchor: anchor))
    .padding(Space.xl)
    .background(.black)
    .crannyThemeRoot(CrannyTheme())
}
