// CrannyTray/UI/TraySymbols.swift — every SF Symbol the Tray draws (DESIGN.md §14.1 "keep them in one enum with a
// unit test asserting each name resolves on macOS 14"). The test checks the system's availability table.
// Additions beyond §14.1's Tray row (pipeline steps): scissors, text.viewfinder, doc.richtext, film, eye.slash,
// arrow.up.forward.app, doc, checkmark — none restricted, all available on macOS 14.
enum TraySymbols {
    static let all: [String] = [
        // Page, zones, widgets
        "tray.full.fill", "tray.and.arrow.down.fill", "dot.radiowaves.up.forward", "folder",
        // Tiles, chips, menus
        "xmark", "checkmark", "exclamationmark", "ellipsis", "chevron.down", "plus", "trash", "link", "doc", "doc.on.doc",
        "square.and.arrow.up", "eye", "arrow.up.forward.app", "arrow.uturn.backward", "wand.and.stars",
        // Pipelines
        "photo.badge.arrow.down", "arrow.triangle.2.circlepath", "square.resize", "doc.zipper", "archivebox",
        "eye.slash", "scissors", "text.viewfinder", "doc.richtext", "film",
    ]
}
