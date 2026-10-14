// CrannyAppShell/Overlay/OverlayCoordinator.swift — owns one `NotchPanelController` per eligible display,
// rebuilds them on screen changes, routes the pointer, keeps at most one open panel and runs the (minimal)
// activity arbitration (ARCHITECTURE.md §4.6, §4.9, §5.4). Intra-shell interface fixed by WP0 (§10.0):
// `init(registry:environment:)`, `start()`, `notchControl`, `play(_:for:)`, `toggleOpen()`, `setPinned(_:)`.
// WP13 owns everything behind it.
import AppKit
import CrannyCore
import CrannyNotchUI
import Foundation
import Observation
import os

private let log = Log.logger(.overlay)

@MainActor @Observable final class OverlayCoordinator {
    /// The `NotchControl` port modules talk to (the same object as `registry.services.notch`).
    @ObservationIgnored let notchControl: ShellNotchControl
    /// Carbon global shortcuts; `ShellAppControl` reads their state.
    @ObservationIgnored let hotKeys = HotKeyCenter()
    /// Mirrors the pin of the open panel (menu bar "Keep Cranny Open").
    private(set) var isPinned = false

    @ObservationIgnored private let registry: ModuleRegistry
    @ObservationIgnored private let environment: ShellEnvironment
    @ObservationIgnored private var controllers: [DisplayKey: NotchPanelController] = [:]
    @ObservationIgnored private let pointer = PointerMonitor()
    @ObservationIgnored private var screenObserver: (any NSObjectProtocol)?
    @ObservationIgnored private let rebuildDebouncer = Debouncer(delay: .milliseconds(250))
    @ObservationIgnored private var tokens: [ObservationToken] = []
    @ObservationIgnored private var playTask: Task<Void, Never>?
    @ObservationIgnored private var menuObservers: [any NSObjectProtocol] = []
    @ObservationIgnored private var trackingMenus = 0

    init(registry: ModuleRegistry, environment: ShellEnvironment) {
        self.registry = registry
        self.environment = environment
        notchControl = (registry.services.notch as? ShellNotchControl) ?? ShellNotchControl()
        notchControl.coordinator = self
        registry.add(activity: notchControl.flashActivity, kind: FlashActivity.kind)
    }

    /// Builds the panels and starts observing. Call once, after every contribution is registered.
    func start() {
        rebuildPanels()
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.rebuildDebouncer.schedule { self?.rebuildPanels() } }
        }
        let settings = registry.services.settings
        tokens.append(observe({ Self.displayPolicy(settings) }) { [weak self] _ in self?.rebuildPanels() })
        tokens.append(observe({ [weak self] in self?.arbitrate() ?? Arbitration() }) { [weak self] result in self?.apply(result) })
        // §4.5: a tracking menu (a context menu in the panel, the menu bar extra's menu) holds the open panel.
        menuObservers = [NSMenu.didBeginTrackingNotification, NSMenu.didEndTrackingNotification].map { name in
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let began = note.name == NSMenu.didBeginTrackingNotification
                MainActor.assumeIsolated { self?.menuTracking(began: began) }          // queue: .main
            }
        }
        pointer.start { [weak self] point in self?.pointerMoved(point) }
        hotKeys.start(registry: registry)
    }

    // MARK: Intra-shell interface (§10.0)

    /// "Show on Notch" from the Settings stage: plays a preview state on the real notch for `duration`.
    func play(_ state: PreviewStageState, for duration: Duration) {
        guard let controller = pointerController ?? controllers.values.first else { return }
        playTask?.cancel()
        switch state {
        case .open: controller.viewModel.send(.open(page: nil, focus: nil, reason: .programmatic))
        case .peek, .activity, .hud: notchControl.flash(symbol: "sparkles", label: "Cranny")       // WP13: sample activities
        case .closed: controller.viewModel.send(.close)
        }
        controller.viewModel.send(.hold("preview", true))
        playTask = Task { [weak controller] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled, let controller else { return }
            controller.viewModel.send(.hold("preview", false))
            controller.viewModel.send(.close)
        }
    }

    /// Open Cranny hot key and menu item: toggles the panel on the pointer's display, with keyboard focus.
    func toggleOpen() {
        if let open = controllers.values.first(where: { $0.viewModel.state.isOpen }) {
            open.viewModel.send(.close)
        } else {
            (pointerController ?? primaryController)?.viewModel.send(.hotKey)
        }
    }

    func setPinned(_ pinned: Bool) {
        let target = controllers.values.first { $0.viewModel.state.isOpen } ?? pointerController ?? primaryController
        if pinned, let target, !target.viewModel.state.isOpen {
            target.viewModel.send(.open(page: nil, focus: nil, reason: .programmatic))
        }
        for controller in controllers.values where controller.viewModel.state.pinned != pinned || controller === target {
            controller.viewModel.send(.setPinned(pinned && controller === target))
        }
        isPinned = pinned
    }

    // MARK: Used by ShellNotchControl

    func open(page: PageID?, focus: WidgetID?, reason: OpenReason) {
        (pointerController ?? primaryController)?.viewModel.send(.open(page: page, focus: focus, reason: reason))
    }
    func closeAll() { for controller in controllers.values { controller.viewModel.send(.close) } }
    func togglePinned() { setPinned(!isPinned) }
    func setHoldOpen(_ hold: Bool, reason: String) {
        for controller in controllers.values { controller.viewModel.send(.hold(reason, hold)) }
    }
    func setFocusMode(_ widget: WidgetID?) {
        guard let controller = controllers.values.first(where: { $0.viewModel.state.isOpen }) else { return }
        controller.viewModel.send(.setMode(widget.map { .focus($0) } ?? .grid))
    }
    func requestKeyboardFocus() {
        controllers.values.first { $0.viewModel.state.isOpen }?.panel.makeKey()
    }
    func shapeFrameOnScreen() -> CGRect? { (pointerController ?? primaryController)?.shapeFrameOnScreen }

    #if DEBUG
    /// Visual QA (`--qa-state`): force a state on the primary display, held open regardless of the pointer.
    func forceQAState(_ state: QAHooks.State, page: PageID?) {
        guard let controller = primaryController else { log.error("QA: no panel"); return }
        controller.viewModel.send(.hold("qa", true))
        switch state {
        case .closed:
            controller.viewModel.send(.close)
        case .compact:
            notchControl.flash(symbol: "hand.wave.fill", label: QAHooks.sampleLabel, duration: 3600)
        case .peek:
            notchControl.flash(symbol: "hand.wave.fill", label: QAHooks.sampleLabel, duration: 3600)
            controller.viewModel.send(.autoPeek(.flash, until: .infinity))
        case .open:
            controller.viewModel.send(.open(page: page, focus: nil, reason: .programmatic))
        }
    }
    #endif

    // MARK: Displays

    /// The policy inputs that decide which displays get a panel (§4.9).
    private struct DisplayPolicy: Equatable {
        var selection: DisplaySelection
        var perDisplay: [DisplayKey: DisplayPreferences]
        var noNotchStyle: NoNotchStyle
    }
    private static func displayPolicy(_ settings: SettingsStore) -> DisplayPolicy {
        DisplayPolicy(selection: settings[CoreSettings.displaySelection], perDisplay: settings[CoreSettings.perDisplay],
                      noNotchStyle: settings[CoreSettings.noNotchStyle])
    }

    /// Eligible displays and their style: `.builtIn` → the built-in display if online, else the primary
    /// display (clamshell removes the built-in screen, R1 §2.6). WP13 adds the pointer-follows policy.
    static func panelScreens(settings: SettingsStore) -> [(screen: NSScreen, key: DisplayKey, style: NoNotchStyle)] {
        let policy = displayPolicy(settings)
        let screens: [NSScreen]
        switch policy.selection {
        case .builtIn:
            let builtIn = NSScreen.screens.first { screen in
                (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)
                    .map { CGDisplayIsBuiltin($0.uint32Value) != 0 } ?? false
            }
            screens = [builtIn ?? NSScreen.screens.first].compactMap { $0 }
        case .pointer, .all:
            screens = NSScreen.screens
        case .custom(let keys):
            let chosen = NSScreen.screens.filter { ThemeResolver.displayKey($0).map(keys.contains) ?? false }
            screens = chosen.isEmpty ? Array(NSScreen.screens.prefix(1)) : chosen
        }
        return screens.compactMap { screen in
            guard let key = ThemeResolver.displayKey(screen) else { return nil }
            let style = policy.perDisplay[key]?.style ?? policy.noNotchStyle
            let hasNotch = screen.safeAreaInsets.top > 0
            if !hasNotch && style == .off { return nil }
            return (screen, key, style)
        }
    }

    private func rebuildPanels() {
        let wanted = Self.panelScreens(settings: registry.services.settings)
        let keys = Set(wanted.map(\.key))
        for (key, controller) in controllers where !keys.contains(key) {
            controller.close()
            controllers[key] = nil
        }
        for entry in wanted {
            if let existing = controllers[entry.key] {
                existing.update(screen: entry.screen, style: entry.style)
            } else {
                let controller = NotchPanelController(screen: entry.screen, key: entry.key, style: entry.style, registry: registry)
                controller.viewModel.pointerSpeed = { [weak self] in self?.pointer.currentSpeed ?? 0 }
                controller.viewModel.openSettings = { [weak self] in self?.registry.services.app.openSettings(nil) }
                controller.onEvent = { [weak self, weak controller] event in
                    guard let self, let controller else { return }
                    self.didEmit(event, from: controller)
                }
                controllers[entry.key] = controller
            }
        }
        apply(arbitrate())
        log.info("panels on \(self.controllers.count, privacy: .public) display(s)")
    }

    private var primaryController: NotchPanelController? {
        controllers.values.first { $0.screen == NSScreen.screens.first } ?? controllers.values.first
    }
    private var pointerController: NotchPanelController? {
        let point = NSEvent.mouseLocation
        return controllers.values.first { NSMouseInRect(point, $0.screen.frame, false) || $0.zoneContains(point) }
    }

    private func pointerMoved(_ point: CGPoint) {
        for controller in controllers.values { controller.pointerMoved(to: point) }
    }

    /// Menus nest (submenus): hold while any tracking session is open.
    private func menuTracking(began: Bool) {
        trackingMenus = max(0, trackingMenus + (began ? 1 : -1))
        setHoldOpen(trackingMenus > 0, reason: NotchMachineState.menuHold)
    }

    /// One open panel at a time; the menu bar's "Keep Cranny Open" follows the open panel's pin.
    private func didEmit(_ event: NotchEvent, from source: NotchPanelController) {
        switch event {
        case .opened:
            for other in controllers.values where other !== source { other.viewModel.send(.close) }
        case .pinned(let pinned):
            isPinned = pinned
        case .closed:
            if !controllers.values.contains(where: { $0.viewModel.state.pinned }) { isPinned = false }
        default:
            break
        }
        notchControl.emit(event)
    }

    // MARK: Arbitration (WP0 minimum of §4.6: highest priority active, unexpired, enabled activity)

    struct Arbitration: Equatable {
        var primary: ActivityID?
        var slot: SlotWidth = .short
    }

    private func arbitrate() -> Arbitration {
        let settings = registry.services.settings
        let preferences = settings[CoreSettings.activityPreferences]
        let paused = environment.areLiveActivitiesPaused
        let now = Date()
        let candidates = registry.activities.enumerated().filter { _, registered in
            let a = registered.activity
            return a.isActive
                && (preferences[registered.id]?.isEnabled ?? registered.kind.isEnabledByDefault)
                && (a.expiresAt.map { $0 > now } ?? true)
                && (!paused || a.priority == .hud)
        }
        let order = settings[CoreSettings.activityOrder]
        let best = candidates.min { lhs, rhs in
            let l = (lhs.element.activity.priority.rawValue, order.firstIndex(of: lhs.element.id) ?? lhs.offset)
            let r = (rhs.element.activity.priority.rawValue, order.firstIndex(of: rhs.element.id) ?? rhs.offset)
            return l < r
        }
        return Arbitration(primary: best?.element.id, slot: best?.element.activity.slot ?? .short)
    }

    private func apply(_ result: Arbitration) {
        for controller in controllers.values where controller.scene.primary != result.primary || controller.scene.primarySlot != result.slot {
            controller.viewModel.setPrimary(result.primary, slot: result.slot)
        }
    }
}
