// CrannyAppShell/State/NotchViewModel.swift — owner of one display's `NotchSceneModel` (ARCHITECTURE.md §4).
// Feeds inputs to the pure `NotchMachine`, executes its effects (dwell/grace sleeps, key focus, events) and
// writes the result into the scene that CrannyNotchUI renders. One per display panel. WP0 skeleton; WP13
// adds arbitration-driven peeks, swipes, drags, hiding and timeouts.
import AppKit
import CrannyCore
import CrannyNotchUI
import Foundation

@MainActor final class NotchViewModel {
    let scene: NotchSceneModel
    private(set) var state = NotchMachineState()
    private let registry: ModuleRegistry
    private var dwellTask: Task<Void, Never>?
    private var graceTask: Task<Void, Never>?
    /// Inputs that arrive while an input is being reduced (an effect such as `makeKey` posts a key-window
    /// notification synchronously) wait here and are reduced in order afterwards.
    private var inbox: [NotchInput] = []
    private var isReducing = false

    // Wired by NotchPanelController / OverlayCoordinator.
    var makeKey: () -> Void = {}
    var relinquishKey: () -> Void = {}
    /// Current pointer speed (pt/s) for the pass-through rule.
    var pointerSpeed: () -> CGFloat = { 0 }
    /// Every `NotchEvent` this display emits (the coordinator forwards them to `NotchControl` observers).
    var onEvent: (NotchEvent) -> Void = { _ in }
    /// Header buttons the shell routes elsewhere (Settings, palette).
    var openSettings: () -> Void = {}

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
        a.activityTapped = { [weak self] _ in self?.send(.click) }
        a.openSettings = { [weak self] in self?.openSettings() }
        a.focusWidget = { [weak self] widget in self?.scene.context.focusedWidget = widget }
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

    /// The arbiter's primary activity for this display (nil = none).
    func setPrimary(_ id: ActivityID?, slot: SlotWidth) {
        scene.primary = id
        scene.primarySlot = slot
        syncScene(config: currentConfig())
    }

    /// Re-derives the scene after settings or the primary changed.
    func refresh() { syncScene(config: currentConfig()) }

    // MARK: Effects

    private func perform(_ effect: NotchEffect) {
        switch effect {
        case .scheduleDwell(let delay):
            dwellTask?.cancel()
            let since = ProcessInfo.processInfo.systemUptime
            dwellTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled, let self else { return }
                let dwell = max(ProcessInfo.processInfo.systemUptime - since, delay)
                self.send(.dwellElapsed(shouldOpen: self.shouldOpen(dwell: dwell)))
            }
        case .cancelDwell:
            dwellTask?.cancel(); dwellTask = nil
        case .scheduleGrace(let delay):
            graceTask?.cancel()
            graceTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled else { return }
                self?.send(.graceElapsed)
            }
        case .cancelGrace:
            graceTask?.cancel(); graceTask = nil
        case .makeKey:
            makeKey()
        case .relinquishKey:
            relinquishKey()
        case .emit(let event):
            onEvent(event)
        }
    }

    private func shouldOpen(dwell: TimeInterval) -> Bool {
        let settings = registry.services.settings
        return HoverIntent.shouldOpen(
            dwell: dwell, pointerSpeed: pointerSpeed(), delay: settings[CoreSettings.hoverDelay],
            mouseButtonDown: NSEvent.pressedMouseButtons != 0,
            optionHeld: settings[CoreSettings.holdOptionToPass] && NSEvent.modifierFlags.contains(.option),
            isFileDrag: false, fullScreenSpace: registry.services.environment.isFullScreenInFront)
    }

    /// A grid page from `CoreSettings.pages` or a page a registered module contributes.
    private func pageExists(_ page: PageID) -> Bool {
        registry.services.settings[CoreSettings.pages].contains { $0.id == page } || registry.pages.contains { $0.id == page }
    }

    private func currentConfig() -> NotchMachineConfig {
        let settings = registry.services.settings
        let lastPage = settings[CoreSettings.lastPage]
        return NotchMachineConfig(
            openMode: settings[CoreSettings.openMode], hoverDelay: settings[CoreSettings.hoverDelay].seconds,
            closeOnLeave: settings[CoreSettings.closeOnLeave], quickPeekOnHover: settings[CoreSettings.quickPeekOnHover],
            lastPage: pageExists(lastPage) ? lastPage : settings[CoreSettings.pages].first?.id ?? .nook, voiceOverRunning: NSWorkspace.shared.isVoiceOverEnabled,
            hasPrimaryActivity: scene.primary != nil)
    }

    // MARK: Scene

    private func syncScene(config: NotchMachineConfig) {
        let phase = NotchMachine.phase(state, config: config)
        if scene.phase != phase { scene.phase = phase }
        switch state.surface {
        case .open(let open):
            if scene.open != open { scene.open = open }
            scene.peekRows = []
        case .peek(let peek):
            scene.open = nil
            if case .auto(let id, _) = peek { scene.peekRows = [id] } else { scene.peekRows = scene.primary.map { [$0] } ?? [] }
        case .closed:
            scene.open = nil
            scene.peekRows = []
        }
        if scene.pinned != state.pinned { scene.pinned = state.pinned }
        var context = scene.context
        context.phase = phase
        context.layout = scene.layout
        context.page = scene.open?.page
        context.openReason = scene.open?.reason
        if scene.open == nil { context.focusedWidget = nil }
        if context != scene.context { scene.context = context }
        scene.openColumns = openColumns(for: scene.open?.page ?? config.lastPage)
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
