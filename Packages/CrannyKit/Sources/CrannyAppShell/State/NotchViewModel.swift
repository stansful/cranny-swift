// CrannyAppShell/State/NotchViewModel.swift — owner of one display's `NotchSceneModel` (ARCHITECTURE.md §4).
// Feeds inputs to the pure `NotchMachine`, runs its effects (one `Task.sleep` per timer, key focus, haptics,
// events, sounds) and writes the result into the scene that CrannyNotchUI renders. One per display panel.
import AppKit
import CrannyCore
import CrannyNotchUI
import Foundation

@MainActor final class NotchViewModel {
    let scene: NotchSceneModel
    private(set) var state = NotchMachineState()
    /// What the arbiter shows here (or the "Show on Notch" sample while it plays).
    private(set) var lineup = Lineup()
    private var arbitrated = Lineup()
    private var lineupOverride: Lineup?
    private let registry: ModuleRegistry
    private var timerTasks: [NotchTimer: Task<Void, Never>] = [:]
    /// Inputs that arrive while an input is being reduced (an effect such as `makeKey` posts a key-window
    /// notification synchronously) wait here and are reduced in order afterwards.
    private var inbox: [NotchInput] = []
    private var isReducing = false
    private var syncedFocus: WidgetID?

    // MARK: Wiring (NotchPanelController / OverlayCoordinator)

    var makeKey: () -> Void = {}
    var relinquishKey: () -> Void = {}
    /// Current pointer speed (pt/s) for the pass-through rule.
    var pointerSpeed: () -> CGFloat = { 0 }
    /// Every `NotchEvent` this display emits (the coordinator forwards them to `NotchControl` observers).
    var onEvent: (NotchEvent) -> Void = { _ in }
    /// Header buttons the shell routes elsewhere (Settings).
    var openSettings: () -> Void = {}
    /// Re-checks full screen right before a hover-open (§5.7 "lazily"); nil = keep the current facts.
    var refreshEnvironment: () -> NotchEnvironment? = { nil }
    /// Swipe-up / VoiceOver "Dismiss" and the satellite click go to the global arbiter.
    var dismissActivity: (ActivityID) -> Void = { _ in }
    var swapSatellite: () -> Void = {}
    /// UI sounds; the coordinator applies `uiSounds` and Demo mode.
    var playSound: (UISound) -> Void = { _ in }
    /// After every scene sync (the controller derives its drop zone and hit area from the state).
    var didSync: () -> Void = {}

    init(scene: NotchSceneModel, registry: ModuleRegistry) {
        self.scene = scene
        self.registry = registry
    }

    /// Callbacks for CrannyNotchUI (the scene is written only here).
    var actions: NotchUIActions {
        var a = NotchUIActions()
        a.open = { [weak self] in self?.send(.click) }
        a.close = { [weak self] in self?.send(.close) }
        a.togglePin = { [weak self] in self.map { $0.send(.setPinned(!$0.state.pinned)) } }
        a.selectPage = { [weak self] page in self?.send(.selectPage(page)) }
        a.setMode = { [weak self] mode in self?.send(.setMode(mode)) }
        a.showPalette = { [weak self] in self?.send(.setMode(.palette)) }
        a.activityTapped = { [weak self] id in self?.openActivity(id) }
        a.satelliteTapped = { [weak self] in self?.swapSatellite() }
        a.dismissActivity = { [weak self] id in self?.dismissActivity(id) }
        a.openSettings = { [weak self] in self?.openSettings() }
        a.focusWidget = { [weak self] widget in
            guard let self, self.scene.context.focusedWidget != widget else { return }
            self.scene.context.focusedWidget = widget
        }
        // Edit layout (⌘E) commits through the owner: the scene is never written by the views (§4.12).
        a.commitLayout = { [weak self] pages in self?.registry.services.settings[CoreSettings.pages] = pages }
        return a
    }

    // MARK: Inputs

    func send(_ input: NotchInput) {
        inbox.append(input)
        guard !isReducing else { return }
        isReducing = true
        defer { isReducing = false }
        while !inbox.isEmpty { reduce(inbox.removeFirst()) }
    }

    /// The arbiter's lineup for this display. A new primary counts as a new activity (§4.4: it brings back
    /// the idle handle and collapsed wings).
    func setLineup(_ next: Lineup) {
        arbitrated = next
        applyLineup(lineupOverride ?? next)
    }

    /// "Show on Notch": shows `lineup` (sample activities in `scene.sampleActivities`) instead of the arbiter's.
    func overrideLineup(_ override: Lineup?) {
        lineupOverride = override
        applyLineup(override ?? arbitrated)
    }

    func setEnvironment(_ environment: NotchEnvironment) {
        guard state.environment != environment else { return }
        send(.environment(environment))
    }

    /// One-shot delight (the coordinator already applied the caps, §4.6 step 7).
    func playDelight(_ moment: DelightMoment) {
        scene.delight = moment
        scene.delightSerial += 1
    }

    /// Hold-⌘ hints (DESIGN.md §6.5) and keyboard-driven focus rings, from `KeyboardRouter`.
    func setCommandHints(_ visible: Bool) {
        guard scene.context.showsCommandHints != visible else { return }
        scene.context.showsCommandHints = visible
        if visible { onEvent(.commandHintsShown) }
    }
    func setKeyboardNavigation(_ on: Bool) {
        if scene.context.keyboardNavigation != on { scene.context.keyboardNavigation = on }
    }

    /// Live rubber-band offset of a two-finger swipe in progress (`GestureRouter`); zero on release.
    func setGestureTranslation(_ translation: CGSize) {
        if scene.gestureTranslation != translation { scene.gestureTranslation = translation }
    }

    /// Re-derives the scene after settings or the layout changed.
    func refresh() { syncScene(config: currentConfig()) }

    /// The geometry hover zones use: the drawn shape, or the closed shape while the idle handle is hidden
    /// (hover is geometric and brings it back, DESIGN.md §3.5); nil while hidden for any other reason.
    var hoverGeometry: NotchGeometry? {
        if state.hidden == .idleHandle { return scene.layout.closed }
        return state.blocksInput ? nil : scene.geometry
    }

    /// The compact wings for menu-bar courtesy (also while retracted): nil without a primary.
    var courtesyGeometry: NotchGeometry? {
        guard lineup.primary != nil, state.isClosed, !state.blocksInput else { return nil }
        return scene.layout.compact(lineup.primarySlot)
    }

    // MARK: Reduction

    private func reduce(_ input: NotchInput) {
        var input = input
        // Only pages that exist are opened: a module page whose module is not registered, or a deleted user
        // page, falls back to the last page (and that to the first grid page), so a tab is always selected.
        switch input {
        case let .open(page?, focus, reason) where !pageExists(page): input = .open(page: nil, focus: focus, reason: reason)
        case .selectPage(let page) where !pageExists(page): return
        default: break
        }
        let config = currentConfig()
        let (next, effects) = NotchMachine.reduce(state, input, now: ProcessInfo.processInfo.systemUptime, config: config)
        state = next
        if case .selectPage(let page) = input, registry.services.settings[CoreSettings.lastPage] != page {
            registry.services.settings[CoreSettings.lastPage] = page
        }
        for effect in effects { perform(effect) }
        syncScene(config: config)
    }

    private func applyLineup(_ next: Lineup) {
        let previous = lineup
        guard next != previous else { return }
        lineup = next
        send(next.primary != nil && next.primary != previous.primary ? .activityChanged : .configChanged)
    }

    private func openActivity(_ id: ActivityID) {
        let widget = activity(id)?.opensWidget
        send(.open(page: widget.flatMap(page(containing:)), focus: widget, reason: .click))
    }

    // MARK: Effects

    private func perform(_ effect: NotchEffect) {
        switch effect {
        case let .schedule(timer, delay): schedule(timer, after: delay)
        case .cancel(let timer):
            timerTasks[timer]?.cancel()
            timerTasks[timer] = nil
        case .makeKey: makeKey()
        case .relinquishKey: relinquishKey()
        case .emit(let event): onEvent(event)
        case .haptic(let pattern): registry.services.haptics.play(pattern)
        case .dismissActivity(let id): dismissActivity(id)
        case let .activityGesture(id, gesture): _ = activity(id)?.handle(gesture)
        case .playSound(let sound): playSound(sound)
        }
    }

    /// One sleep per timer, never repeating (§9.2). The dwell decides `shouldOpen` when it fires.
    private func schedule(_ timer: NotchTimer, after delay: TimeInterval) {
        timerTasks[timer]?.cancel()
        let since = ProcessInfo.processInfo.systemUptime
        timerTasks[timer] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(delay, 0)))
            guard !Task.isCancelled, let self else { return }
            self.timerTasks[timer] = nil
            if timer == .dwell {
                if let environment = self.refreshEnvironment() { self.setEnvironment(environment) }
                let dwell = max(ProcessInfo.processInfo.systemUptime - since, delay)
                self.send(.dwellElapsed(shouldOpen: self.shouldOpen(dwell: dwell)))
            } else {
                self.send(.timerElapsed(timer))
            }
        }
    }

    private func shouldOpen(dwell: TimeInterval) -> Bool {
        let settings = registry.services.settings
        return HoverIntent.shouldOpen(
            dwell: dwell, pointerSpeed: pointerSpeed(), delay: settings[CoreSettings.hoverDelay],
            mouseButtonDown: NSEvent.pressedMouseButtons != 0,
            optionHeld: settings[CoreSettings.holdOptionToPass] && NSEvent.modifierFlags.contains(.option),
            isFileDrag: false, fullScreenSpace: state.environment.restrictsToAlerts)
    }

    // MARK: Lookups

    private func activity(_ id: ActivityID) -> (any LiveActivity)? {
        scene.sampleActivities[id] ?? registry.activity(id)?.activity
    }

    /// A grid page from `CoreSettings.pages` or a page a registered module contributes.
    private func pageExists(_ page: PageID) -> Bool {
        registry.services.settings[CoreSettings.pages].contains { $0.id == page } || registry.pages.contains { $0.id == page }
    }

    /// The grid page that holds a widget (clicking an activity opens its widget there).
    private func page(containing widget: WidgetID) -> PageID? {
        registry.services.settings[CoreSettings.pages].first { $0.items.contains { $0.widget == widget } }?.id
    }

    private func currentConfig() -> NotchMachineConfig {
        let settings = registry.services.settings
        let preferences = scene.context.display.flatMap { settings[CoreSettings.perDisplay][$0] } ?? DisplayPreferences()
        let lastPage = settings[CoreSettings.lastPage]
        let widget = lineup.primary.flatMap { activity($0)?.opensWidget }
        var c = NotchMachineConfig()
        c.openMode = settings[CoreSettings.openMode]
        c.hoverDelay = settings[CoreSettings.hoverDelay].seconds
        c.closeOnLeave = settings[CoreSettings.closeOnLeave]
        c.quickPeekOnHover = settings[CoreSettings.quickPeekOnHover] && preferences.showsPeeks
        c.lastPage = pageExists(lastPage) ? lastPage : settings[CoreSettings.pages].first?.id ?? .nook
        c.voiceOverRunning = NSWorkspace.shared.isVoiceOverEnabled
        c.primary = lineup.primary
        c.satellite = lineup.satellite
        c.primaryWidget = widget
        c.primaryWidgetPage = widget.flatMap(page(containing:))
        c.openInactivityTimeout = settings[CoreSettings.openInactivityTimeout]
        c.compactInactivityTimeout = settings[CoreSettings.compactInactivityTimeout]
        c.hasHandle = !scene.layout.metrics.hasNotch
        c.hidesIdleHandle = settings[CoreSettings.hideHandleWhenIdle]
        c.handleIdleDelay = settings[CoreSettings.handleIdleDelay]
        c.swipeOpenClose = settings[CoreSettings.swipeOpenClose]
        c.swipeToDismiss = settings[CoreSettings.swipeToDismiss]
        c.trackSwipe = settings[CoreSettings.trackSwipe]
        c.acceptsFileDrags = registry.services.tray != nil
        c.menuBarCourtesy = settings[CoreSettings.menuBarCourtesy]
        return c
    }

    // MARK: Scene

    private func syncScene(config: NotchMachineConfig) {
        let phase = NotchMachine.phase(state, config: config)
        if scene.phase != phase { scene.phase = phase }
        if scene.primary != lineup.primary { scene.primary = lineup.primary }
        if scene.satellite != lineup.satellite { scene.satellite = lineup.satellite }
        if scene.primarySlot != lineup.primarySlot { scene.primarySlot = lineup.primarySlot }
        let rows: [ActivityID]
        switch state.surface {
        case .open: rows = []
        case .peek(.auto(let id, _)): rows = [id]
        case .peek(.hover): rows = lineup.hoverPeekRows
        case .closed: rows = []
        }
        if scene.peekRows != rows { scene.peekRows = rows }
        let opening = scene.open == nil && state.openState != nil
        if scene.open != state.openState { scene.open = state.openState }
        if scene.pinned != state.pinned { scene.pinned = state.pinned }

        var context = scene.context
        context.phase = phase
        context.layout = scene.layout
        context.page = state.openState?.page
        context.openReason = state.openState?.reason
        context.redactsPersonalData = state.environment.demoMode && registry.services.settings[CoreSettings.demoRedactsCalendar]
        let focus = state.openState?.focus
        if focus != syncedFocus { context.focusedWidget = focus; syncedFocus = focus }
        if state.openState == nil {
            context.focusedWidget = nil
            context.showsCommandHints = false
            syncedFocus = nil
        }
        // Focus rings follow the way it was opened; KeyboardRouter updates them on later keys and clicks.
        if opening { context.keyboardNavigation = state.openState?.reason == .keyboard }
        if context != scene.context { scene.context = context }
        let columns = openColumns(for: state.openState?.page ?? config.lastPage)
        if scene.openColumns != columns { scene.openColumns = columns }
        didSync()
    }

    /// Sum of the visible widget widths on a grid page (module pages use the Home page's width).
    private func openColumns(for page: PageID) -> Int {
        let pages = registry.services.settings[CoreSettings.pages]
        guard let grid = pages.first(where: { $0.id == page }) ?? pages.first else { return 10 }
        let cells = grid.items.reduce(0) { sum, item in
            sum + (registry.widget(item.widget)?.sizes.clamp(item.cells) ?? max(item.cells, 1))
        }
        return max(cells, 1)
    }
}
