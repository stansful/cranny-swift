// CrannyTray/Platform/TraySystem.swift — the Tray's side effects outside the notch: pasteboard, Finder, Quick Look,
// VoiceOver announcements. Behind a protocol so tests never touch the user's clipboard, Finder or screen.
import AppKit
import CrannyCore
import Foundation
import SwiftUI

@MainActor protocol TraySystem: AnyObject {
    /// Plain text on the general pasteboard (Copy paths, Copy text).
    func copy(text: String)
    /// File URLs on the general pasteboard (⌘C: paste the files in Finder or Mail).
    func copy(files: [URL])
    func reveal(_ urls: [URL])
    func open(_ urls: [URL])
    /// Quick Look on `urls`, starting at `index`.
    func quickLook(_ urls: [URL], at index: Int)
    func closeQuickLook()
    var isQuickLookVisible: Bool { get }
    /// A VoiceOver announcement (pipeline finished).
    func announce(_ message: String)
    /// Moves files Cranny just wrote to the Trash (Undo); recoverable, never a hard delete.
    func trash(_ urls: [URL]) async
}

/// The real thing. Writing the general pasteboard never triggers the paste alert (only reading does, R1 §5.1).
@MainActor final class LiveTraySystem: TraySystem {
    private let quickLook = QuickLookPresenter()
    private let announcer: Announcer

    /// `announcer`: the app's (`services.announcer`), so a pipeline result shares the 10-s limit with every alert.
    init(announcer: Announcer) { self.announcer = announcer }

    func copy(text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    func copy(files: [URL]) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects(files.map { $0 as NSURL })
    }

    func reveal(_ urls: [URL]) { NSWorkspace.shared.activateFileViewerSelecting(urls) }

    func open(_ urls: [URL]) { for url in urls { NSWorkspace.shared.open(url) } }

    func quickLook(_ urls: [URL], at index: Int) { quickLook.show(urls, at: index) }
    func closeQuickLook() { quickLook.close() }
    var isQuickLookVisible: Bool { quickLook.isVisible }

    func announce(_ message: String) {
        announcer.announce(message, kind: .result)
    }

    func trash(_ urls: [URL]) async {
        await Self.trashOffMain(urls)
    }

    @concurrent private static func trashOffMain(_ urls: [URL]) async {
        for url in urls { try? FileManager.default.trashItem(at: url, resultingItemURL: nil) }
    }
}

/// A `TraySystem` that only records (tests and previews never touch the pasteboard, Finder or the screen).
@MainActor final class RecordingTraySystem: TraySystem {
    private(set) var calls: [String] = []
    private(set) var copiedText: String?
    private(set) var trashed: [URL] = []
    var isQuickLookVisible = false

    func copy(text: String) { copiedText = text; calls.append("copyText") }
    func copy(files: [URL]) { calls.append("copyFiles(\(files.count))") }
    func reveal(_ urls: [URL]) { calls.append("reveal(\(urls.count))") }
    func open(_ urls: [URL]) { calls.append("open(\(urls.count))") }
    func quickLook(_ urls: [URL], at index: Int) { isQuickLookVisible = true; calls.append("quickLook(\(urls.count),\(index))") }
    func closeQuickLook() { isQuickLookVisible = false; calls.append("closeQuickLook") }
    func announce(_ message: String) { calls.append("announce") }
    func trash(_ urls: [URL]) async {
        trashed += urls                                                     // recorded only, never deleted
        calls.append("trash(\(urls.count))")
    }
}
