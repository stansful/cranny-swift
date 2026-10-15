// The Settings window's lifetime (ARCHITECTURE.md §5.9, §9.2): closing it releases the window, its hosting
// controller and the SwiftUI tree, while the controller keeps the `SettingsSession`, so opening it again at a page
// shows that page with the search, the sidebar's pick and the Reset All Undo offer of before, where the window was
// (`.inMemory` has no frame autosave, as in a QA run). Nothing is ordered in and nothing is activated:
// `preparedWindow(at:)` builds the window `show(page:)` would bring forward.
import AppKit
import CrannyCore
import Foundation
import Testing
@testable import CrannyAppShell
@testable import CrannySettingsUI

@Test func closingSettingsReleasesTheWindowAndReopeningKeepsTheSession() async throws {
    _ = NSApplication.shared
    let registry = ModuleRegistry(services: .preview())
    let defaults = ShellDefaults.inMemory
    let controller = SettingsWindowController(registry: registry, defaults: defaults)
    let frame = CGRect(x: 40, y: 60, width: 900, height: 640)
    weak var closedWindow: NSWindow?
    weak var closedHost: NSViewController?
    let session = try autoreleasepool {
        let window = controller.preparedWindow(at: .about)
        window.contentView?.layoutSubtreeIfNeeded()                             // the SwiftUI tree is built
        closedWindow = window
        closedHost = window.contentViewController
        #expect(closedHost != nil)
        let session = try #require(controller.session)
        #expect(session.currentPage == .about)
        session.query = "motion"
        session.sidebarSelection = .pane(.about)
        session.resetAll.resetAll()
        window.setFrame(frame, display: false)                                  // the person moved it
        window.close()
        return session
    }
    #expect(controller.window == nil && controller.session === session)
    for _ in 0..<150 where closedWindow != nil || closedHost != nil { try await Task.sleep(for: .milliseconds(20)) }
    #expect(closedWindow == nil, "the closed window is still alive")
    #expect(closedHost == nil, "the closed window's hosting controller is still alive")
    #expect(session.stage.wallpaper == nil)

    // Reopened at a page: a new window around the same session, on that page, with the search and the Undo offer.
    let reopened = controller.preparedWindow(at: "appearance#motion")
    #expect(controller.session === session && controller.window === reopened)
    #expect(session.currentPage == .appearance && session.query == "motion" && session.resetAll.canUndo)
    #expect(reopened.frame == frame)                                            // where the closed one was
    let title = try #require(SettingsRootView.pages(registry: registry).first { $0.id == .appearance }?.title)
    reopened.contentView?.layoutSubtreeIfNeeded()
    for _ in 0..<150 where reopened.title != title { try await Task.sleep(for: .milliseconds(20)) }
    #expect(reopened.title == title)                                            // the new tree shows the pane
    #expect(session.sidebarSelection == .pane(.appearance))                     // the sidebar followed the pane

    // While it is open, showing Settings again brings back the same window.
    #expect(controller.preparedWindow(at: .appearance) === reopened && session.currentPage == .appearance)

    // Closed and opened again on the same pane: the stage keeps the state picked there (a new pane would set its own).
    session.stage.select(.peek)
    reopened.close()
    defaults.defaults.removeObject(forKey: "CrannySettingsLastPane")
    let third = controller.preparedWindow(at: nil)
    third.contentView?.layoutSubtreeIfNeeded()
    // The new tree took its pane (it reports it after setting the stage's state, in the same change handler).
    for _ in 0..<150 where defaults.defaults.string(forKey: "CrannySettingsLastPane") == nil {
        try await Task.sleep(for: .milliseconds(20))
    }
    #expect(defaults.defaults.string(forKey: "CrannySettingsLastPane") == "appearance")
    #expect(third !== reopened && session.currentPage == .appearance && session.stage.state == .peek)
    third.close()
    session.resetAll.dismiss()
}
