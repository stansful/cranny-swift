// CrannyAppShell/Overlay/OverlayCoordinator.swift — owns one `NotchPanelController` per eligible display, rebuilds
// them on display changes, routes the pointer and file drags, keeps at most one open panel and forwards every event
// to `NotchControl` observers (ARCHITECTURE.md §4.9, §5.4–§5.5). Arbitration lives in `+Activities`, the
// `NotchControl` backing and "Show on Notch" in `+Control`. Intra-shell interface fixed by WP0 (§10.0):
// `init(registry:environment:)`, `start()`, `notchControl`, `hotKeys`, `play(_:for:)`, `toggleOpen()`, `setPinned(_:)`.
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
    var isPinned = false
    /// The display the current `NotchControl.flash` belongs to (the pointer's when it was requested, §4.9).
    var flashDisplay: DisplayKey?
    /// The display under the pointer (alerts, peeks and the HUD follow it; `.pointer` selection shows only it).
    var pointerDisplay: DisplayKey?

    @ObservationIgnored let registry: ModuleRegistry
    @ObservationIgnored let environment: ShellEnvironment
    @ObservationIgnored var controllers: [DisplayKey: NotchPanelController] = [:]
    /// Every connected display (with or without a panel), for the allocation-free pointer lookup.
    @ObservationIgnored var screens: [(key: DisplayKey, id: CGDirectDisplayID, frame: CGRect)] = []
    @ObservationIgnored let pointer = PointerMonitor()
    @ObservationIgnored let drags = DragDetector()
    @ObservationIgnored let displayChanges = DisplayChangeObserver()
    @ObservationIgnored var tokens: [ObservationToken] = []
    @ObservationIgnored var menuObservers: [any NSObjectProtocol] = []
    @ObservationIgnored var trackingMenus = 0
    // Arbitration (+Activities)
    @ObservationIgnored var arbiter = ActivityArbiter()
    @ObservationIgnored var ranked: [ActivitySnapshot] = []
    @ObservationIgnored var expiryTask: Task<Void, Never>?
    @ObservationIgnored var delights = DelightScheduler()
    // Control (+Control)
    @ObservationIgnored var playTask: Task<Void, Never>?
    @ObservationIgnored var preview: (key: DisplayKey, id: ActivityID)?
    @ObservationIgnored var isCalibrating = false
    #if DEBUG
    /// Visual QA forces a state even while the screen is locked (`--qa-state`, QAHooks).
    @ObservationIgnored var qaForcesVisibility = false
    #endif

    init(registry: ModuleRegistry, environment: ShellEnvironment) {
        self.registry = registry
        self.environment = environment
        notchControl = (registry.services.notch as? ShellNotchControl) ?? ShellNotchControl()
        notchControl.coordinator = self
        registry.add(activity: notchControl.flashActivity, kind: FlashActivity.kind)
        notchControl.sharing.shapeFrame = { [weak self] in self?.shapeFrameOnScreen() }
        notchControl.sharing.setHold = { [weak self] on in self?.setHoldOpen(on, reason: NotchMachineState.shareHold) }
    }

    /// Builds the panels and starts observing. Call once, after every contribution is registered.
    func start() {
        rebuildPanels()
        displayChanges.start { [weak self] in self?.rebuildPanels() }
        let settings = registry.services.settings
        tokens.append(observe({ Self.displayPolicy(settings) }) { [weak self] _ in self?.rebuildPanels() })
        startArbitration()
        // §4.5: a tracking menu (a context menu in the panel, the menu bar extra's menu) holds the open panel.
        menuObservers = [NSMenu.didBeginTrackingNotification, NSMenu.didEndTrackingNotification].map { name in
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let began = note.name == NSMenu.didBeginTrackingNotification
                MainActor.assumeIsolated { self?.menuTracking(began: began) }          // queue: .main
            }
        }
        pointer.start { [weak self] point, kind in self?.pointerEvent(point, kind: kind) }
        hotKeys.start(registry: registry)
    }

    // MARK: Intra-shell interface (§10.0)

    /// Open Cranny hot key and menu item: toggles the panel on the pointer's display, with keyboard focus.
    func toggleOpen() {
        if let open = openController {
            open.viewModel.send(.close)
        } else {
            refreshEnvironmentNow()
            alertController?.viewModel.send(.hotKey)
        }
    }

    func setPinned(_ pinned: Bool) {
        let target = openController ?? alertController
        if pinned, let target, !target.viewModel.state.isOpen {
            target.viewModel.send(.open(page: nil, focus: nil, reason: .programmatic))
        }
        for controller in controllers.values where controller.viewModel.state.pinned != pinned || controller === target {
            controller.viewModel.send(.setPinned(pinned && controller === target))
        }
        isPinned = pinned && target != nil
    }

    // MARK: Displays (§4.9, §5.4)

    /// The policy inputs that decide which displays get a panel.
    private struct DisplayPolicy: Equatable {
        var selection: DisplaySelection
        var perDisplay: [DisplayKey: DisplayPreferences]
        var noNotchStyle: NoNotchStyle
    }
    private static func displayPolicy(_ settings: SettingsStore) -> DisplayPolicy {
        DisplayPolicy(selection: settings[CoreSettings.displaySelection], perDisplay: settings[CoreSettings.perDisplay],
                      noNotchStyle: settings[CoreSettings.noNotchStyle])
    }

    /// Eligible displays and their style (`--diagnostics` lists them; `DisplayCatalog.placements` decides).
    static func panelScreens(settings: SettingsStore) -> [(screen: NSScreen, key: DisplayKey, style: NoNotchStyle)] {
        let policy = displayPolicy(settings)
        let all = DisplayCatalog.descriptors()
        let placements = DisplayCatalog.placements(for: all.map(\.descriptor), selection: policy.selection,
                                                   perDisplay: policy.perDisplay, noNotchStyle: policy.noNotchStyle)
        return placements.compactMap { placement in
            all.first { $0.descriptor.key == placement.key }.map { ($0.screen, placement.key, placement.style) }
        }
    }

    func rebuildPanels() {
        let all = DisplayCatalog.descriptors()
        screens = all.map { ($0.descriptor.key, $0.descriptor.displayID, $0.screen.frame) }
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
                controllers[entry.key] = makeController(screen: entry.screen, key: entry.key, style: entry.style)
            }
        }
        updatePointerDisplay(NSEvent.mouseLocation)
        environment.refreshFullScreen()
        applyDisplayFacts()
        log.info("panels on \(self.controllers.count, privacy: .public) of \(self.screens.count, privacy: .public) display(s)")
    }

    private func makeController(screen: NSScreen, key: DisplayKey, style: NoNotchStyle) -> NotchPanelController {
        let controller = NotchPanelController(screen: screen, key: key, style: style, registry: registry)
        let viewModel = controller.viewModel
        viewModel.pointerSpeed = { [weak self] in self?.pointer.currentSpeed ?? 0 }
        viewModel.openSettings = { [weak self] in self?.registry.services.app.openSettings(nil) }
        viewModel.refreshEnvironment = { [weak self, weak controller] in
            guard let self, let controller else { return nil }
            self.environment.refreshFullScreen()
            return self.environmentFacts(for: controller.key)
        }
        viewModel.dismissActivity = { [weak self] id in self?.dismiss(id) }
        viewModel.swapSatellite = { [weak self, weak controller] in
            guard let self, let controller else { return }
            self.swapSatellite(on: controller)
        }
        viewModel.playSound = { [weak self] sound in self?.play(sound) }
        controller.onEvent = { [weak self, weak controller] event in
            guard let self, let controller else { return }
            self.didEmit(event, from: controller)
        }
        controller.onDropFinished = { [weak self, weak controller] in self?.dropFinished(on: controller) }
        if isCalibrating { controller.setCalibrating(true) }
        return controller
    }

    /// The panel on the primary display (menu bar screen), else any.
    var primaryController: NotchPanelController? {
        screens.first.flatMap { controllers[$0.key] } ?? controllers.values.first
    }
    /// Where alerts, peeks, the hot key and programmatic opens go: the pointer's display, else the primary one.
    var alertController: NotchPanelController? {
        pointerDisplay.flatMap { controllers[$0] } ?? primaryController
    }
    var openController: NotchPanelController? {
        controllers.values.first { $0.viewModel.state.isOpen }
    }

    // MARK: Pointer and file drags (§5.5)

    private func pointerEvent(_ point: CGPoint, kind: PointerMonitor.Kind) {
        updatePointerDisplay(point)
        if let change = drags.update(kind), change == nil {
            for controller in controllers.values { controller.dragEnded() }
        }
        for controller in controllers.values {
            controller.pointerMoved(to: point)
            if let contents = drags.current { controller.dragMoved(to: point, contents: contents) }
        }
    }

    /// A drop on `source` ends the drag everywhere. The detector may never see the source's mouse-up, so it would
    /// never report the end: every other panel the drag passed (its catch state, `drag` hold and enlarged drop zone)
    /// lets go now. The dropping panel keeps its zones until the drop router has delivered the payload.
    func dropFinished(on source: NotchPanelController?) {
        drags.reset()
        for controller in controllers.values {
            if controller === source { controller.dropFinished() } else { controller.dragEnded() }
        }
    }

    /// O(displays), no allocation: the cached frames, the top row included (y == maxY, R1 §2.5).
    private func updatePointerDisplay(_ point: CGPoint) {
        var found: (key: DisplayKey, id: CGDirectDisplayID)?
        for screen in screens where point.x >= screen.frame.minX && point.x < screen.frame.maxX
            && point.y >= screen.frame.minY && point.y <= screen.frame.maxY {
            found = (screen.key, screen.id)
            break
        }
        guard let found, found.key != pointerDisplay else { return }
        pointerDisplay = found.key
        environment.setPointerDisplay(found.id)
        // Now, not on the next observation hop: sliding along the menu bar onto the other display's notch must
        // find its panel already shown (`.pointer` selection) and its alerts already moved.
        if !controllers.isEmpty { applyDisplayFacts() }
    }

    /// Menus nest (submenus): hold while any tracking session is open.
    private func menuTracking(began: Bool) {
        trackingMenus = max(0, trackingMenus + (began ? 1 : -1))
        setHoldOpen(trackingMenus > 0, reason: NotchMachineState.menuHold)
    }

    // MARK: Events

    /// One open panel at a time; the menu bar's "Keep Cranny Open" follows the open panel's pin.
    private func didEmit(_ event: NotchEvent, from source: NotchPanelController) {
        switch event {
        case .opened:
            for other in controllers.values where other !== source { other.viewModel.send(.close) }
            if delights.firstOpen() { playDelight(.firstLight, on: source.key) }
        case .pinned(let pinned):
            isPinned = pinned
        case .closed:
            if !controllers.values.contains(where: { $0.viewModel.state.pinned }) { isPinned = false }
        case .filesCaught:
            playDelight(.gulp, on: source.key)
        default:
            break
        }
        notchControl.emit(event)
    }

    /// "Pop" on a catch (DESIGN.md §14.3): system sounds by name, only with UI sounds on, never in Demo mode.
    private func play(_ sound: UISound) {
        guard registry.services.settings[CoreSettings.uiSounds], !environment.isDemoMode else { return }
        NSSound(named: NSSound.Name(sound.rawValue))?.play()
    }
}
