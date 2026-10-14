// CrannySettingsUI/Stage/StageController.swift — the owner (and only writer) of the preview stage's `NotchSceneModel`
// (ARCHITECTURE §4.12, D14, D21). It renders the REAL notch views fed by the LIVE settings: theme and layout come
// from `ThemeResolver` exactly as the shell computes them, sample activities from `RegisteredActivity.makeSample`
// (stand-ins for the well-known ones until their modules provide samples), and every settings change animates the
// stage with the real motion tokens. Simulate chips play one short script; nothing loops.
//
// Energy: it observes settings only between `start()` and `stop()` (the stage is on screen), and the scripts are
// sleeps to deadlines. The view drops the canvas while the window is occluded.
import AppKit
import CrannyCore
import CrannyNotchUI
import Foundation
import Observation
import SwiftUI

@MainActor @Observable final class StageController {
    /// The scene the canvas renders. Written only here.
    let model: NotchSceneModel
    /// The picker state (Closed · Activity · Peek · Open · HUD).
    private(set) var state: PreviewStageState
    /// The page the Open state shows (Layout & Widgets follows the page being edited).
    private(set) var page: PageID = .nook
    /// The open Nook's mode on the stage: `.editLayout` while Layout & Widgets is shown (DESIGN.md §11.1, §6.6).
    private(set) var openMode: NookMode = .grid
    /// The chip whose script is playing, if any.
    private(set) var playing: SimulateChip?
    /// The display the stage imitates, and whether Cranny is turned off on it (written by the appearance extension).
    var displayName: String?
    var isOffOnDisplay = false
    /// The wallpaper under the stage (nil = neutral gradient).
    var wallpaper: WallpaperSource.Miniature?

    @ObservationIgnored let registry: ModuleRegistry
    @ObservationIgnored var currentScreen: NSScreen?
    @ObservationIgnored private var samples: [ActivityID: any LiveActivity] = [:]
    @ObservationIgnored private var tokens: [ObservationToken] = []
    @ObservationIgnored private var script: Task<Void, Never>?
    @ObservationIgnored private var screenObserver: (any NSObjectProtocol)?
    @ObservationIgnored private var lastMotion: MotionPersonality

    init(registry: ModuleRegistry, state: PreviewStageState) {
        self.registry = registry
        self.state = state
        let settings = registry.services.settings
        model = NotchSceneModel(layout: NotchLayout(metrics: .reference), theme: CrannyTheme())
        model.context.isPreview = true
        samples = Self.makeSamples(registry: registry)
        model.sampleActivities = samples
        page = settings[CoreSettings.pages].first?.id ?? .nook
        lastMotion = settings[CoreSettings.motion]
        chooseScreen()
        applyAppearance(animated: false)
        apply(currentScene, animated: false)
    }

    // MARK: Lifecycle

    /// Starts following settings and display changes (call when the stage appears).
    func start() {
        guard tokens.isEmpty else { return }
        let settings = registry.services.settings
        tokens.append(observe({ [weak self] in self?.appearanceInputs() }) { [weak self] _ in
            self?.applyAppearance(animated: true)
        })
        tokens.append(observe({ [weak self] in self?.castInputs() }) { [weak self] _ in
            self?.refreshScene(animated: true)
        })
        tokens.append(observe({ settings[CoreSettings.motion] }) { [weak self] motion in self?.replayForMotion(motion) })
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                                                object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.chooseScreen()
                self?.applyAppearance(animated: false)
            }
        }
        Task { await loadWallpaper() }
    }

    /// Stops observing and cancels a playing chip (the stage disappeared or its window is hidden).
    func stop() {
        tokens.forEach { $0.cancel() }
        tokens.removeAll()
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
        cancelScript(settle: true)
    }

    // MARK: Controls

    func select(_ newState: PreviewStageState) {
        cancelScript(settle: false)
        state = newState
        apply(currentScene, animated: true)
    }

    /// Layout & Widgets: the Open state shows the page being edited.
    func show(page newPage: PageID) {
        guard newPage != page else { return }
        page = newPage
        if playing == nil, state == .open { apply(currentScene, animated: true) }
    }

    /// Layout & Widgets puts the open Nook into edit mode, so the layout can be edited on the stage itself (NotchUI
    /// draws the edit chrome and reports changes through `commitLayout`). Only the grid and edit modes apply here.
    func setOpenMode(_ mode: NookMode) {
        guard mode == .grid || mode == .editLayout, mode != openMode else { return }
        openMode = mode
        if playing == nil, state == .open { apply(currentScene, animated: true) }
    }

    /// Plays a chip once, then settles on the picker state.
    func simulate(_ chip: SimulateChip) {
        let settings = registry.services.settings
        let steps = StageScript.steps(for: chip, base: currentScene, cast: cast, page: page,
                                      peekDuration: settings[CoreSettings.peekDuration],
                                      showsSatellite: settings[CoreSettings.satellite])
        guard !steps.isEmpty else { return }
        cancelScript(settle: false)
        playing = chip
        script = Task { [weak self] in
            for step in steps {
                if step.delay > .zero { try? await Task.sleep(for: step.delay) }
                guard !Task.isCancelled, let self else { return }
                self.apply(step.scene, animated: true)
            }
            self?.playing = nil
        }
    }

    /// Chips offered: those whose sample exists (Drop file always).
    var availableChips: [SimulateChip] {
        SimulateChip.allCases.filter { $0.activity.map { samples[$0] != nil } ?? true }
    }

    /// "Show on Notch": the picker state on the real notch for 5 s (§11.2).
    func showOnNotch() { registry.services.app.showOnNotch(state) }

    // MARK: Scenes

    private var currentScene: StageScene {
        let settings = registry.services.settings
        return StageScript.scene(for: state, cast: cast, page: page, mode: openMode, showsSatellite: settings[CoreSettings.satellite])
    }

    /// Enabled samples, ongoing ones in the user's order (Live Activities toggles and order apply live).
    var cast: StageCast {
        let settings = registry.services.settings
        let preferences = settings[CoreSettings.activityPreferences]
        let order = settings[CoreSettings.activityOrder]
        let registered = registry.activities.map(\.id)
        let enabled = samples.keys.filter { id in
            preferences[id]?.isEnabled ?? registry.activity(id)?.kind.isEnabledByDefault ?? true
        }
        let ongoing = enabled.filter { (registry.activity($0)?.kind.defaultPriority ?? samples[$0]?.priority) == .ongoing }
        let fallbackOrder: [ActivityID] = [.nowPlaying, .timerRunning]
        func rank(_ id: ActivityID) -> (Int, Int, Int) {
            (order.firstIndex(of: id) ?? .max, registered.firstIndex(of: id) ?? .max, fallbackOrder.firstIndex(of: id) ?? .max)
        }
        return StageCast(ongoing: ongoing.sorted { rank($0) < rank($1) }, available: Set(enabled))
    }

    private func apply(_ scene: StageScene, animated: Bool) {
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let animation = animated ? CrannyMotion.animation(scene.motion, personality: model.theme.motion, reduceMotion: reduceMotion) : nil
        let primarySlot = scene.primary.flatMap { samples[$0]?.slot } ?? .short
        let columns = openColumns(for: scene.open?.page ?? page)
        withAnimation(animation) {
            if model.primary != scene.primary { model.primary = scene.primary }
            if model.primarySlot != primarySlot { model.primarySlot = primarySlot }
            if model.satellite != scene.satellite { model.satellite = scene.satellite }
            if model.peekRows != scene.peekRows { model.peekRows = scene.peekRows }
            if model.open != scene.open { model.open = scene.open }
            if model.openColumns != columns { model.openColumns = columns }
            if model.phase != scene.phase { model.phase = scene.phase }
            var context = model.context
            context.phase = scene.phase
            context.layout = model.layout
            context.page = scene.open?.page
            context.openReason = scene.open?.reason
            if context != model.context { model.context = context }
        }
        model.ambient = ambientPalette(primary: scene.primary)
        if let delight = scene.delight, allowsDelight(reduceMotion: reduceMotion) {
            model.delight = delight
            model.delightSerial += 1
        }
    }

    /// The caps of DESIGN.md §5.5 that apply on a stage: none under Calm, Instant or Reduce Motion.
    private func allowsDelight(reduceMotion: Bool) -> Bool {
        !reduceMotion && model.theme.motion != .calm && model.theme.motion != .instant
    }

    private func openColumns(for page: PageID) -> Int {
        let items = registry.services.settings[CoreSettings.pages].first { $0.id == page }?.items ?? []
        return StageScript.openColumns(items: items, sizes: { [registry] in registry.widget($0)?.sizes },
                                       maxColumns: model.layout.maxColumns)
    }

    private func ambientPalette(primary: ActivityID?) -> AmbientPalette {
        let settings = registry.services.settings
        return ThemeResolver.ambientPalette(topActivity: primary.flatMap { samples[$0]?.palette },
                                            accent: settings[CoreSettings.accent], systemAccent: AccentResolver.systemAccent())
    }

    /// Re-applies the picker state (open width, satellite, toggles) unless a chip is playing.
    func refreshScene(animated: Bool) {
        guard playing == nil else { return }
        apply(currentScene, animated: animated)
    }

    private func cancelScript(settle: Bool) {
        script?.cancel()
        script = nil
        if playing != nil {
            playing = nil
            if settle { apply(currentScene, animated: false) }
        }
    }

    /// A new Motion personality replays the current state's entrance, so the difference is visible (not under
    /// Reduce Motion or Instant, where the stage just updates).
    private func replayForMotion(_ motion: MotionPersonality) {
        defer { lastMotion = motion }
        guard lastMotion != motion, playing == nil, state != .closed, motion != .instant,
              !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        let target = currentScene
        apply(StageScene(phase: .idle, motion: .close), animated: true)
        script = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            self?.apply(target, animated: true)
        }
    }
}
