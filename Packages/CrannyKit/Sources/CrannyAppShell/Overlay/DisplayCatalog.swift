// CrannyAppShell/Overlay/DisplayCatalog.swift — which displays get a panel and how each is measured
// (ARCHITECTURE.md §4.9, §5.4, DESIGN.md §3.1, §3.7). `placements` is the pure display-selection policy;
// the rest reads NSScreen / CoreGraphics. Keys are display UUIDs (`ThemeResolver.displayKey`), stable across
// reconnects. Clamshell removes the built-in screen from `NSScreen.screens` (R1 §2.6).
import AppKit
import CoreGraphics
import CrannyCore
import CrannyNotchUI
import Foundation

/// What the display-selection rule needs to know about a connected display (`DisplayCatalog.shown`): the panels
/// (`DisplayDescriptor`) and the menu bar's Show On ▸ rows (`ConnectedDisplay`) answer it with one rule.
nonisolated protocol DisplayFacts {
    var key: DisplayKey { get }
    var isBuiltIn: Bool { get }
    var hasNotch: Bool { get }
}

/// One connected display, as the selection policy sees it.
nonisolated struct DisplayDescriptor: Equatable, Sendable, DisplayFacts {
    var key: DisplayKey
    var displayID: CGDirectDisplayID
    var isBuiltIn: Bool
    var hasNotch: Bool
    /// `NSScreen.screens[0]`: the display with the menu bar.
    var isPrimary: Bool
}

/// A display that gets a panel, and its style.
nonisolated struct PanelPlacement: Equatable, Sendable {
    var key: DisplayKey
    var style: NoNotchStyle
}

nonisolated enum DisplayCatalog {
    /// §4.9: `.builtIn` → the built-in display if online, else the primary · `.pointer` → every display (only the
    /// pointer's one is visible, `followsPointer`) · `.all` · `.custom(keys)` (none connected → the primary).
    /// Displays whose style resolves to `.off` get no panel; a hardware notch is always drawn.
    static func placements(for displays: [DisplayDescriptor], selection: DisplaySelection,
                           perDisplay: [DisplayKey: DisplayPreferences], noNotchStyle: NoNotchStyle) -> [PanelPlacement] {
        shown(displays, primary: displays.first(where: \.isPrimary) ?? displays.first, selection: selection,
              perDisplay: perDisplay, noNotchStyle: noNotchStyle)
            .map { PanelPlacement(key: $0.key, style: perDisplay[$0.key]?.style ?? noNotchStyle) }
    }

    /// The displays that show Cranny, in `displays` order: the selection (with its fallbacks to the built-in display or
    /// `primary`), minus the displays whose style hides it. The one rule behind the panels and the Show On ▸ checkmarks.
    static func shown<D: DisplayFacts>(_ displays: [D], primary: D?, selection: DisplaySelection,
                                       perDisplay: [DisplayKey: DisplayPreferences], noNotchStyle: NoNotchStyle) -> [D] {
        let chosen: [D]
        switch selection {
        case .builtIn:
            chosen = [displays.first(where: \.isBuiltIn) ?? primary].compactMap { $0 }
        case .pointer, .all:
            chosen = displays
        case .custom(let keys):
            let matching = displays.filter { keys.contains($0.key) }
            chosen = matching.isEmpty ? [primary].compactMap { $0 } : matching
        }
        // One rule with the Settings stage (Core): an explicit per-display Off hides Cranny on any display;
        // the no-notch style applies only where there is no notch.
        return chosen.filter { showsCranny($0, perDisplay: perDisplay, noNotchStyle: noNotchStyle) }
    }

    /// Whether the display's style lets Cranny appear on it (`DisplayPreferences.showsCranny`).
    static func showsCranny(_ display: some DisplayFacts, perDisplay: [DisplayKey: DisplayPreferences],
                            noNotchStyle: NoNotchStyle) -> Bool {
        DisplayPreferences.showsCranny(perDisplay[display.key], noNotchStyle: noNotchStyle, hasNotch: display.hasNotch)
    }

    /// `.pointer`: panels everywhere, only the pointer's display shows one (others are `notThisDisplay`).
    static func followsPointer(_ selection: DisplaySelection) -> Bool { selection == .pointer }

    // MARK: Screens

    /// The `CGDirectDisplayID` of a screen (`NSScreenNumber`; `cgDirectDisplayID` is macOS 26+).
    @MainActor static func displayID(of screen: NSScreen) -> CGDirectDisplayID? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber).map { $0.uint32Value }
    }

    /// Every connected screen with its descriptor (screens without a UUID are skipped).
    @MainActor static func descriptors() -> [(screen: NSScreen, descriptor: DisplayDescriptor)] {
        let screens = NSScreen.screens
        return screens.enumerated().compactMap { index, screen in
            guard let key = ThemeResolver.displayKey(screen), let id = displayID(of: screen) else { return nil }
            return (screen, DisplayDescriptor(key: key, displayID: id, isBuiltIn: CGDisplayIsBuiltin(id) != 0,
                                              hasNotch: screen.safeAreaInsets.top > 0, isPrimary: index == 0))
        }
    }

    /// `NotchMetrics.measure`, plus the Window Server menu-bar height when the menu bar auto-hides
    /// (`visibleFrame` then includes the top strip; DESIGN.md §3.1 step 2, R1 §2.3).
    @MainActor static func metrics(for screen: NSScreen) -> NotchMetrics {
        var metrics = NotchMetrics.measure(screen)
        guard menuBarAutoHides(on: screen, hasNotch: metrics.hasNotch), let id = displayID(of: screen) else {
            return metrics
        }
        let windows = FullScreenDetector.snapshot()
        if let height = FullScreenDetector.menuBarHeight(on: CGDisplayBounds(id), windows: windows) {
            metrics.bandHeight = height
        }
        return metrics
    }

    /// A display without a notch whose menu bar auto-hides (`visibleFrame` reaches the top edge): `metrics(for:)`
    /// reads its menu bar's height from the window list then.
    @MainActor static func menuBarAutoHides(on screen: NSScreen, hasNotch: Bool) -> Bool {
        !hasNotch && screen.frame.maxY - screen.visibleFrame.maxY <= 0
    }

    /// The display under a point (AppKit screen coordinates; the top row, y == maxY, counts, R1 §2.5).
    @MainActor static func screen(containing point: CGPoint) -> NSScreen? {
        NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) }
            ?? NSScreen.screens.first { $0.frame.insetBy(dx: 0, dy: -1).contains(point) }
    }
}

/// Display hot-plug, resolution and arrangement changes (§4.9): `didChangeScreenParametersNotification` plus
/// `CGDisplayRegisterReconfigurationCallback`, debounced 250 ms (both fire several times per change), and
/// re-validation on wake and Space changes. `pending` hears each change at once (the pointer tap forwards every event
/// until the rebuild, `isPending`).
@MainActor final class DisplayChangeObserver {
    private var observers: [(NotificationCenter, any NSObjectProtocol)] = []
    private let debouncer = Debouncer(delay: .milliseconds(250))
    private var onChange: () -> Void = {}
    private var onPending: () -> Void = {}
    private var registered = false
    /// A change waits for its debounced `onChange`.
    private(set) var isPending = false
    /// Target of the C reconfiguration callback (which cannot capture context).
    private static weak var current: DisplayChangeObserver?

    func start(pending: @escaping () -> Void = {}, _ onChange: @escaping () -> Void) {
        self.onChange = onChange
        onPending = pending
        Self.current = self
        listen(.default, NSApplication.didChangeScreenParametersNotification)
        let workspace = NSWorkspace.shared.notificationCenter
        listen(workspace, NSWorkspace.didWakeNotification)
        listen(workspace, NSWorkspace.screensDidWakeNotification)
        listen(workspace, NSWorkspace.activeSpaceDidChangeNotification)
        registered = CGDisplayRegisterReconfigurationCallback(Self.callback, nil) == .success
    }

    func stop() {
        for (center, token) in observers { center.removeObserver(token) }
        observers.removeAll()
        debouncer.cancel()
        isPending = false
        if registered { CGDisplayRemoveReconfigurationCallback(Self.callback, nil) }
        registered = false
    }

    /// One function pointer, so the same one can be removed again.
    private nonisolated static let callback: CGDisplayReconfigurationCallBack = { _, flags, _ in
        guard !flags.contains(.beginConfigurationFlag) else { return }
        // Delivered on the registering (main) thread's run loop; hop explicitly anyway.
        DispatchQueue.main.async { MainActor.assumeIsolated { DisplayChangeObserver.current?.changed() } }
    }

    private func listen(_ center: NotificationCenter, _ name: Notification.Name) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.changed() }                               // queue: .main
        }
        observers.append((center, token))
    }

    private func changed() {
        isPending = true
        onPending()
        debouncer.schedule { [weak self] in
            guard let self else { return }
            self.isPending = false
            self.onChange()
        }
    }
}
