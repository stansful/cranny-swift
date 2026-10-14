// CrannyTray/UI/TrayContextMenu.swift — the tile's context menu (DESIGN.md §8.1: Open, Reveal in Finder, Quick Look,
// Copy Path, Share…, Remove) as an AppKit `NSMenu` (the tile's AppKit layer receives the right click), and the same
// commands as VoiceOver actions so nothing is hover- or pointer-only (§16). While a pipeline runs on the tile, Stop
// leads both (the hover ✕ on the ring is not the only way to cancel; keys: ⌘.).
import AppKit
import CrannyCore
import Foundation
import SwiftUI

@MainActor enum TrayContextMenu {
    static func make(for id: UUID, store: TrayStore) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        if let job = store.job(for: id) {
            menu.addItem(ClosureMenuItem.make(title: TrayItemCommand.stopTitle, symbol: "xmark") { store.cancel(job.id) })
            menu.addItem(.separator())
        }
        for command in TrayItemCommand.allCases {
            if command == .remove { menu.addItem(.separator()) }
            menu.addItem(ClosureMenuItem.make(title: command.title, symbol: command.symbol) { command.perform(on: id, store: store) })
        }
        return menu
    }
}

/// The per-item commands shared by the context menu and VoiceOver.
enum TrayItemCommand: CaseIterable {
    case open, reveal, quickLook, copyPath, airDrop, share, remove

    var title: String {
        switch self {
        case .open: String(localized: "Open", bundle: .module, comment: "Tray tile: context menu item and VoiceOver action")
        case .reveal: String(localized: "Reveal in Finder", bundle: .module, comment: "Tray action and pipeline step: show the files in Finder")
        case .quickLook: String(localized: "Quick Look", bundle: .module, comment: "Tray tile: context menu item and VoiceOver action (Apple's feature name)")
        case .copyPath: String(localized: "Copy Path", bundle: .module, comment: "Tray tile: context menu item and VoiceOver action")
        case .airDrop: "AirDrop"
        case .share: String(localized: "Share…", bundle: .module, comment: "Tray tile: context menu item and VoiceOver action; opens the share picker")
        case .remove: String(localized: "Remove from Tray", bundle: .module, comment: "Tray tile: hover button and menu item that removes the file from the Tray")
        }
    }

    var symbol: String {
        switch self {
        case .open: "arrow.up.forward.app"
        case .reveal: "folder"
        case .quickLook: "eye"
        case .copyPath: "link"
        case .airDrop: "dot.radiowaves.up.forward"
        case .share: "square.and.arrow.up"
        case .remove: "trash"
        }
    }

    /// Stop a running pipeline: the tile's ✕ on the ring, the chip, the menu item and the VoiceOver action.
    static var stopTitle: String {
        String(localized: "Stop", bundle: .module, comment: "Tray: stop a running pipeline (tile button, chip, context menu item, VoiceOver action)")
    }

    /// Hide the error tile of a failed drop (hover button, VoiceOver action).
    static var dismissTitle: String {
        String(localized: "Dismiss", bundle: .module, comment: "Tray tile: hide a failed run of dropped files")
    }

    @MainActor func perform(on id: UUID, store: TrayStore) {
        switch self {
        case .open: store.open(id)
        case .reveal: store.reveal(id)
        case .quickLook: store.toggleQuickLook(id)
        case .copyPath: store.copyPaths(id)
        case .airDrop: store.airDrop(id)
        case .share: store.share(id)
        case .remove: store.removeTargets(id)
        }
    }
}

/// VoiceOver named actions for a tile.
struct TrayItemActions: ViewModifier {
    let store: TrayStore
    let id: UUID
    func body(content: Content) -> some View {
        content
            .accessibilityActions {
                if let job = store.job(for: id) {
                    Button { store.cancel(job.id) } label: { Text(verbatim: TrayItemCommand.stopTitle) }
                }
            }
            .accessibilityAction(named: Text(verbatim: TrayItemCommand.open.title)) { TrayItemCommand.open.perform(on: id, store: store) }
            .accessibilityAction(named: Text(verbatim: TrayItemCommand.quickLook.title)) { TrayItemCommand.quickLook.perform(on: id, store: store) }
            .accessibilityAction(named: Text(verbatim: TrayItemCommand.reveal.title)) { TrayItemCommand.reveal.perform(on: id, store: store) }
            .accessibilityAction(named: Text(verbatim: TrayItemCommand.copyPath.title)) { TrayItemCommand.copyPath.perform(on: id, store: store) }
            .accessibilityAction(named: Text(verbatim: TrayItemCommand.airDrop.title)) { TrayItemCommand.airDrop.perform(on: id, store: store) }
            .accessibilityAction(named: Text(verbatim: TrayItemCommand.share.title)) { TrayItemCommand.share.perform(on: id, store: store) }
            .accessibilityAction(named: Text(verbatim: TrayItemCommand.remove.title)) { TrayItemCommand.remove.perform(on: id, store: store) }
    }
}

/// An `NSMenuItem` that runs a closure (the item keeps its target alive through `representedObject`).
@MainActor enum ClosureMenuItem {
    static func make(title: String, symbol: String?, handler: @escaping @MainActor () -> Void) -> NSMenuItem {
        let target = MenuAction(handler)
        let item = NSMenuItem(title: title, action: #selector(MenuAction.run(_:)), keyEquivalent: "")
        item.target = target
        item.representedObject = target
        if let symbol { item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) }
        return item
    }
}

@MainActor private final class MenuAction: NSObject {
    private let handler: @MainActor () -> Void
    init(_ handler: @escaping @MainActor () -> Void) { self.handler = handler }
    @objc func run(_ sender: Any?) { handler() }
}
