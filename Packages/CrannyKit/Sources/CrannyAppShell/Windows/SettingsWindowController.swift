// CrannyAppShell/Windows/SettingsWindowController.swift — the Settings window (ARCHITECTURE.md §5.9, D11; DESIGN.md §11.1).
// An AppKit-managed NSWindow hosting `SettingsRootView`, so any pane (or row: "general#hoverDelay") can be opened
// programmatically from an agent app (no SwiftUI `Settings` scene). 860 × 620 by default, 780 × 560 minimum; the frame
// is autosaved (not in a Debug QA run with its own defaults suite) and the last pane is restored (`ShellDefaults`).
// SwiftUI drives the toolbar and title (`sceneBridgingOptions`), so the sidebar and toolbar get the system's Liquid
// Glass on macOS 26+ and Cranny adds none of its own. The controller keeps one `SettingsSession` for the run: opening
// a pane navigates it, so the Reset All Undo offer, the search and the preview stage survive. Closing releases the
// window, its hosting controller and the SwiftUI tree (an ordered-out hosting controller still re-evaluates bodies on
// every observed change), as the Welcome window does; the next open builds them again around the same session, at the
// autosaved frame, so only pane-local view state (scroll positions, a pane's own picks) starts fresh.
import AppKit
import CrannyCore
import CrannySettingsUI
import SwiftUI

@MainActor final class SettingsWindowController: NSObject, NSWindowDelegate {
    /// Not a Cranny setting (Reset All keeps it): the pane shown last, restored when Settings opens without one.
    private static let lastPaneKey = "CrannySettingsLastPane"
    /// AppKit's frame autosave name (the frame is stored under "NSWindow Frame CrannySettings").
    private static let frameAutosaveName = "CrannySettings"

    private let registry: ModuleRegistry
    private let defaults: UserDefaults
    /// False in a QA run with its own suite: AppKit's frame autosave would write the standard domain.
    private let autosavesFrame: Bool
    /// Only while Settings is open: released on close.
    private(set) var window: NSWindow?
    /// The window's state, kept for the run (also while no window exists); `show(page:)` navigates it.
    private(set) var session: SettingsSession?
    /// The app that was frontmost before Settings opened gets activation back on close.
    private var previousApp: NSRunningApplication?

    /// `defaults` is the app's `ShellDefaults` (tests pass an in-memory one).
    init(registry: ModuleRegistry, defaults: ShellDefaults) {
        self.registry = registry
        self.defaults = defaults.defaults
        autosavesFrame = defaults.autosavesWindowFrames
    }

    /// Opens (or brings forward) Settings, showing `page` if given ("pane" or "pane#row"); nil shows the pane shown last.
    /// Call in response to a user action (cooperative activation, DESIGN.md §11.1).
    func show(page: SettingsPageID?) {
        let front = NSWorkspace.shared.frontmostApplication
        if front?.processIdentifier != ProcessInfo.processInfo.processIdentifier { previousApp = front }
        let window = preparedWindow(at: page)
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    /// The Settings window at `page` (nil keeps the session's pane; the first open restores the last one), not yet
    /// ordered in: the open window navigated, never rebuilt (the Undo offer, the search and the stage stay), or a new
    /// one built around the kept session. `show(page:)` brings it forward; tests call this alone.
    func preparedWindow(at page: SettingsPageID?) -> NSWindow {
        if let window, let session {
            session.open(page)
            return window
        }
        let session: SettingsSession
        if let kept = self.session {
            kept.open(page)
            session = kept
        } else {
            session = SettingsSession(registry: registry, initialPage: page ?? lastPage)
            self.session = session
            #if DEBUG
            scheduleQASnapshot()
            #endif
        }
        let window = makeWindow(session: session)
        self.window = window
        return window
    }

    /// A new window hosting `session`; the frame autosave restores where it was.
    private func makeWindow(session: SettingsSession) -> NSWindow {
        let host = NSHostingController(rootView: SettingsRootView(session: session) { [weak self] shown in
            self?.rememberLastPane(shown)
        })
        host.sizingOptions = []
        host.sceneBridgingOptions = [.title, .toolbars]
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 860, height: 620),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.contentViewController = host
        window.contentMinSize = CGSize(width: 780, height: 560)
        window.setContentSize(CGSize(width: 860, height: 620))
        window.isReleasedWhenClosed = false
        window.toolbarStyle = .unified
        window.titlebarSeparatorStyle = .automatic
        window.tabbingMode = .disallowed
        window.collectionBehavior.insert(.fullScreenNone)
        window.delegate = self
        window.center()
        if autosavesFrame { window.setFrameAutosaveName(Self.frameAutosaveName) }
        #if DEBUG
        applyQAAppearance(to: window)
        #endif
        return window
    }

    func windowWillClose(_ notification: Notification) {
        // Cooperative activation hand-back (§5.9, [UNVERIFIED] R1 §3.5).
        if let previousApp, !previousApp.isTerminated { previousApp.activate() }
        previousApp = nil
        // Release the window (AppKit lets go of it once the close is done) and with it the hosting controller and the
        // SwiftUI tree; keep the session. The frame is already saved: giving up the autosave name keeps it saved and
        // lets the next window take the name even if this one is still alive then (a name is unique per live window).
        if autosavesFrame { window?.setFrameAutosaveName("") }
        window = nil
        session?.windowDidClose()
    }

    #if DEBUG
    /// Visual QA (Debug only): `-CrannyQAAppearance light|dark` pins this window's appearance (Settings otherwise
    /// follows the system, DESIGN.md §11.1).
    private func applyQAAppearance(to window: NSWindow) {
        switch defaults.string(forKey: "CrannyQAAppearance") {
        case "light": window.appearance = NSAppearance(named: .aqua)
        case "dark": window.appearance = NSAppearance(named: .darkAqua)
        default: break
        }
    }

    /// Visual QA (Debug only): `-CrannyQASnapshot <file.png>` renders the window's own view hierarchy to a PNG after
    /// `-CrannyQASnapshotDelay` seconds (default 3). Unlike `screencapture`, it works while the displays sleep.
    /// `-CrannyQAViewReport <file.txt>` writes, at the same moment, the window's table views with their row counts and
    /// registered drag types (evidence that a list's `onMove` reordering is wired, without synthesizing a drag).
    private func scheduleQASnapshot() {
        let snapshot = defaults.string(forKey: "CrannyQASnapshot")
        let report = defaults.string(forKey: "CrannyQAViewReport")
        guard snapshot != nil || report != nil else { return }
        let delay = defaults.double(forKey: "CrannyQASnapshotDelay")
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay > 0 ? delay : 3))
            if let report { self?.writeViewReport(to: URL(fileURLWithPath: report)) }
            if let snapshot { self?.writeSnapshot(to: URL(fileURLWithPath: snapshot)) }
        }
    }

    private func writeViewReport(to url: URL) {
        guard let root = window?.contentView?.superview ?? window?.contentView else { return }
        var lines: [String] = []
        func visit(_ view: NSView) {
            if let table = view as? NSTableView {
                let types = table.registeredDraggedTypes.map(\.rawValue).sorted()
                lines.append("\(type(of: table)) rows=\(table.numberOfRows) dragTypes=\(types)")
            }
            view.subviews.forEach(visit)
        }
        visit(root)
        try? (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    private func writeSnapshot(to url: URL) {
        guard let view = window?.contentView?.superview ?? window?.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
    #endif

    private var lastPage: SettingsPageID? {
        defaults.string(forKey: Self.lastPaneKey).map(SettingsPageID.init(rawValue:))
    }

    /// Restored when Settings opens without a pane (kept in the app's `ShellDefaults`).
    func rememberLastPane(_ page: SettingsPageID) {
        defaults.set(page.rawValue, forKey: Self.lastPaneKey)
    }
}
