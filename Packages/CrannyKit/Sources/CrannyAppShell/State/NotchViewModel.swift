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
    let registry: ModuleRegistry
    private var timerTasks: [NotchTimer: Task<Void, Never>] = [:]
    /// Inputs that arrive while an input is being reduced (an effect such as `makeKey` posts a key-window
    /// notification synchronously) wait here and are reduced in order afterwards.
    private var inbox: [NotchInput] = []
    private var isReducing = false
    private var syncedFocus: WidgetID?
    /// The dwell (its start time) whose full-screen facts were re-read already: once per hover, not per retry.
    private var dwellEnvironmentChecked: TimeInterval?

    // MARK: Wiring (NotchPanelController / OverlayCoordinator)

    var makeKey: () -> Void = {}
    var relinquishKey: () -> Void = {}
    /// Current pointer speed (pt/s) for the pass-through rule.
    var pointerSpeed: () -> CGFloat = { 0 }
    /// A mouse button is down / ⌥ is held right now (the other two pass-through rules).
    var pointerKeys: () -> (buttonDown: Bool, optionDown: Bool) = {
        (NSEvent.pressedMouseButtons != 0, NSEvent.modifierFlags.contains(.option))
    }
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

    /// Moves the open panel's focus to `widget` (type-to-capture), first showing the grid page that holds it when
    /// it is not on the current one, so the captured text is visible.
    func focus(_ widget: WidgetID?) {
        if let widget, let open = state.openState, !page(open.page, holds: widget), let page = page(containing: widget) {
            send(.selectPage(page))
        }
        send(.setFocus(widget))
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

    /// The satellite's click target in canvas coordinates (top-left origin) while it shows, beside the shape as
    /// drawn (the compact wings, or the closed notch once the inactivity timeout collapsed them): the bubble
    /// padded to at least 32 × 24 (`SatelliteMetrics.hitFrame`, DESIGN.md §2.3).
    func satelliteFrame(in canvas: CGRect) -> CGRect? {
        guard scene.satellite != nil, state.isClosed, state.hidden == nil else { return nil }
        return SatelliteMetrics.hitFrame(beside: scene.geometry, layout: scene.layout, in: canvas)
    }

    /// The compact wings for menu-bar courtesy (also while retracted): nil without a primary.
    var courtesyGeometry: NotchGeometry? {
        guard lineup.primary != nil, state.isClosed, !state.blocksInput else { return nil }
        return scene.layout.compact(lineup.primarySlot, label: scene.middleLabelWidth)
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
        timerTasks[timer] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(delay, 0)))
            guard !Task.isCancelled, let self else { return }
            self.timerTasks[timer] = nil
            if timer == .dwell { self.dwellElapsed() } else { self.send(.timerElapsed(timer)) }
        }
    }

    /// The dwell elapsed. The length is measured against what the machine requires now (`requiredDwell`: the
    /// quick-peek dwell over compact, whatever the hover delay; longer in a full-screen Space), the pointer
    /// against HoverIntent's pass-through rules (button down, ⌥ held, too fast).
    private func dwellElapsed() {
        guard case .dwelling(let since) = state.hover else { send(.dwellElapsed(shouldOpen: false)); return }   // clears the timer
        // §5.7 "lazily, right before a hover-open": one window-list query per hover, not one per retry.
        if dwellEnvironmentChecked != since {
            dwellEnvironmentChecked = since
            if let environment = refreshEnvironment() { setEnvironment(environment) }
        }
        let required = NotchMachine.requiredDwell(state, config: currentConfig())
        let elapsed = ProcessInfo.processInfo.systemUptime - since
        let keys = pointerKeys(), speed = pointerSpeed()
        let optionHeld = registry.services.settings[CoreSettings.holdOptionToPass] && keys.optionDown
        // Only the dwell length is checked here; `delay: .instant` leaves HoverIntent the three pointer rules.
        let aiming = HoverIntent.shouldOpen(dwell: elapsed, pointerSpeed: speed, delay: .instant,
                                            mouseButtonDown: keys.buttonDown, optionHeld: optionHeld,
                                            isFileDrag: false, fullScreenSpace: false)
        let tooFastOnly = !keys.buttonDown && !optionHeld && speed > HoverIntent.passThroughSpeed
        if elapsed + Self.dwellTolerance < required {
            send(.dwellRetry)                                  // a full-screen Space was found: dwell the rest
        } else if aiming {
            send(.dwellElapsed(shouldOpen: true))
        } else {
            // Only the speed said no: still travelling, so look again instead of giving up until re-entry.
            send(tooFastOnly ? .dwellRetry : .dwellElapsed(shouldOpen: false))
        }
    }

    /// A sleep never wakes early by more than this (clock granularity between the reducer's `now` and ours).
    private static let dwellTolerance: TimeInterval = 0.005

    // MARK: Scene

    private func syncScene(config: NotchMachineConfig) {
        let phase = NotchMachine.phase(state, config: config)
        if scene.phase != phase { scene.phase = phase }
        if scene.primary != lineup.primary { scene.primary = lineup.primary }
        let satellite = NotchMachine.satelliteIsVisible(state, config: config) ? lineup.satellite : nil
        if scene.satellite != satellite { scene.satellite = satellite }
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
}
