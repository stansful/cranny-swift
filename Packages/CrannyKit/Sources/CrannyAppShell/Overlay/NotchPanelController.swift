// CrannyAppShell/Overlay/NotchPanelController.swift — one display's panel (ARCHITECTURE.md §5.3).
// A fixed-size, non-activating panel at level 26, top-centred on the notch (screen centre without one); every
// morph is SwiftUI inside it. The controller wires the panel to its view model and input routers (hover zones,
// swipes, keys, drops, key focus) and keeps theme, layout and light in step with the settings by observation.
// What every pointer event or every appearance would rebuild is kept until its inputs change: the hover zones
// (`PanelZonesCache`) and the display's measurements (`DisplayMeasure`); the middle label is measured again only
// when its text or the notch unit changes, and not at all on a notched display.
import AppKit
import CrannyCore
import CrannyNotchUI
import SwiftUI

@MainActor final class NotchPanelController {
    let key: DisplayKey
    let panel: NotchPanel
    let root: NotchRootView
    let scene: NotchSceneModel
    let viewModel: NotchViewModel
    let chrome = PanelChrome()
    private(set) var screen: NSScreen
    private(set) var style: NoNotchStyle
    private let registry: ModuleRegistry
    /// The pointer as this panel sees it: hover zones, enter/leave, a menu's region after it closed (§4.3, §4.5).
    let hover = PanelHover()
    private let focus: FocusManager
    private let keyboard: KeyboardRouter
    private let gestures: GestureRouter
    private let drops: DropRouter
    private var tokens: [ObservationToken] = []
    private var occlusionObserver: (any NSObjectProtocol)?
    /// `panelZones` until something they derive from changes.
    private var zonesCache = PanelZonesCache()
    /// The display as the appearance reads it, measured when the display changes (`init`, `update(screen:style:)`).
    private var display: DisplayMeasure
    /// The last middle label measured, at a notch unit, and its width (`middleLabelWidth(of:layout:)`).
    private var labelMemo: (label: String?, unit: CGFloat, width: CGFloat)?
    /// A layout or canvas-size change that arrived while the surface was not closed (applied once it has been
    /// closed long enough for the morph to land).
    private var layoutIsPending = false
    private var pendingTask: Task<Void, Never>?
    /// How long the surface stays closed before a pending canvas change is applied (the close spring lands).
    static let settleDelay: Duration = .milliseconds(600)
    /// Every event of this display, forwarded by the coordinator to `NotchControl` observers.
    var onEvent: (NotchEvent) -> Void = { _ in }
    /// A drop finished on this panel (the coordinator resets its drag detector).
    var onDropFinished: () -> Void = {}

    init(screen: NSScreen, key: DisplayKey, style: NoNotchStyle, registry: ModuleRegistry) {
        self.screen = screen; self.key = key; self.style = style; self.registry = registry
        let display = DisplayMeasure(screen)
        self.display = display
        let appearance = Self.appearance(screen: screen, display: display, style: style, registry: registry, primary: nil)
        scene = NotchSceneModel(layout: appearance.layout, theme: appearance.theme)
        scene.ambient = appearance.ambient
        scene.context.display = key
        viewModel = NotchViewModel(scene: scene, registry: registry)

        let frame = Self.panelFrame(canvas: appearance.layout.canvasSize, screen: screen)
        panel = NotchPanel(frame: frame)
        root = NotchRootView(frame: CGRect(origin: .zero, size: frame.size))
        // The hosting view takes the same direction from AppKit and SwiftUI mirrors the canvas with it.
        viewModel.layoutDirection = root.userInterfaceLayoutDirection == .rightToLeft ? .rightToLeft : .leftToRight
        focus = FocusManager(panel: panel)
        keyboard = KeyboardRouter(panel: panel, viewModel: viewModel, registry: registry)
        gestures = GestureRouter(scene: scene, viewModel: viewModel, registry: registry)
        drops = DropRouter(scene: scene, viewModel: viewModel, registry: registry)

        let content = PanelContentView(scene: scene, registry: registry, actions: viewModel.actions, chrome: chrome)
        let host = NotchHostingView(rootView: content)
        host.sizingOptions = []
        host.safeAreaRegions = []                 // no 32–38 pt jump on notched displays
        host.frame = root.bounds
        host.autoresizingMask = [.width, .height]
        root.addSubview(host)
        panel.contentView = root
        root.interactiveRect = { [weak self] in self?.interactiveRect() ?? .zero }
        root.dropTarget = drops
        panel.scrollInterceptor = { [weak self] event in
            guard let self else { return false }
            return self.gestures.handle(event, in: self.root)
        }
        wire()
        viewModel.refresh()
        panel.orderFrontRegardless()                // never activates the app
    }

    private func wire() {
        viewModel.makeKey = { [weak self] in self?.focus.makeKey() }
        viewModel.relinquishKey = { [weak self] in self?.focus.relinquishKeyIfNeeded() }
        viewModel.onEvent = { [weak self] event in self?.didEmit(event) }
        focus.onHold = { [weak self] reason, on in self?.viewModel.send(.hold(reason, on)) }
        hover.zones = { [weak self] in self?.panelZones }
        hover.send = { [weak self] input in self?.viewModel.send(input) }
        drops.onDropFinished = { [weak self] in self?.onDropFinished() }
        focus.start()
        keyboard.start()
        // Theme, layout and light follow the settings and the primary activity's palette (observed, no polling).
        tokens.append(observe({ [weak self] in
            self.map {
                Self.appearance(screen: $0.screen, display: $0.display, style: $0.style, registry: $0.registry,
                                primary: $0.scene.primary)
            }
        }) { [weak self] appearance in
            if let appearance { self?.apply(appearance) }
        })
        // The floating island's middle label (open issue 3): measured here, drawn by NotchUI, so the shape
        // (`geometry`), the wings and the hit area agree on its width. Follows the primary, its label and the layout.
        // A notched display (or style Off) has no middle label: the layout is read first, so there the primary's label
        // is never read and its changes (Now Playing's every snapshot) never wake this observer.
        let labelWidth: @MainActor () -> CGFloat = { [weak self] in
            guard let self else { return 0 }
            let layout = self.scene.layout
            guard !layout.metrics.hasNotch, layout.noNotchStyle != .off else { return 0 }
            let label = self.scene.primary.flatMap { self.viewModel.activity($0)?.middleLabel }
            return self.middleLabelWidth(of: label, layout: layout)
        }
        scene.middleLabelWidth = labelWidth()
        tokens.append(observe(labelWidth) { [weak self] width in
            guard let self, self.scene.middleLabelWidth != width else { return }
            self.scene.middleLabelWidth = width
            self.viewModel.refresh()
        })
        // Effects pause while the panel is covered, the screen is locked or the displays sleep (§9.2).
        updateVisibility()
        occlusionObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification, object: panel, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateVisibility() }
        }
        // The open shape follows every layout change (⌘E, Settings, presets, Reset, Undo), not only the next input.
        tokens.append(viewModel.observeLayout())
        // Timeouts and per-display toggles re-arm the machine's idle timers.
        let settings = registry.services.settings
        tokens.append(observe({ [key] in Self.timerSettings(settings, display: key) }) { [weak self] _ in
            self?.viewModel.send(.configChanged)
        })
        // The drop zone (and with it the hit area) follows the drag state; a pending canvas change waits for
        // the surface to be closed, and a menu's region ends with the open surface (a peek ends without a `.closed`
        // event, so the state is watched, not events).
        viewModel.didSync = { [weak self] in
            guard let self else { return }
            self.zonesCache.invalidate()                                          // state, lineup or scene changed
            let zone = self.dropZoneInCanvas()
            if self.chrome.dropZone != zone { self.chrome.dropZone = zone }
            self.hover.surfaceChanged()
            self.applyPendingWhenSettled()
        }
    }

    /// The display changed (hot-plug, arrangement, resolution): the panel follows it at once; a new canvas size
    /// or layout waits until the surface is closed (`PanelFramePlan`).
    func update(screen: NSScreen, style: NoNotchStyle) {
        self.screen = screen; self.style = style
        zonesCache.invalidate()
        display = DisplayMeasure(screen)
        apply(Self.appearance(screen: screen, display: display, style: style, registry: registry, primary: scene.primary))
        if !panel.isVisible { panel.orderFrontRegardless() }
    }

    /// `NotchSelectionFocus`: key status for a selection, which does not hold the panel open (`KeyHold`).
    func takeSelectionFocus() { focus.makeKey(forTyping: false) }

    private func updateVisibility() {
        let visible = panel.occlusionState.contains(.visible)
        if scene.isVisibleOnScreen != visible { scene.isVisibleOnScreen = visible }
    }

    func close() {
        if let occlusionObserver { NotificationCenter.default.removeObserver(occlusionObserver) }
        occlusionObserver = nil
        pendingTask?.cancel()
        tokens.removeAll()
        keyboard.stop()
        focus.relinquishKeyIfNeeded()
        focus.stop()
        panel.scrollInterceptor = nil
        root.dropTarget = nil
        panel.orderOut(nil)
        panel.close()
    }

    /// Appearance ▸ Notch fit: outline + loupe, the shape frozen in the breath.
    func setCalibrating(_ on: Bool) {
        if chrome.calibrating != on { chrome.calibrating = on }
        viewModel.send(.calibration(on))
    }

    // MARK: Pointer

    /// Screen coordinates (AppKit, bottom-left origin) of the shape body as currently drawn.
    var shapeFrameOnScreen: CGRect {
        let g = scene.geometry
        return CGRect(x: panel.frame.midX - g.outerWidth / 2, y: panel.frame.maxY - g.bottom,
                      width: g.outerWidth, height: g.height)
    }

    /// The hover zones in screen coordinates (with a menu's region while it lasts), or nil while hidden (§4.3,
    /// DESIGN.md §3.6).
    var hoverZones: HoverZones? { hover.hoverZones }

    /// The zones of the shape as drawn, without a menu's region: built once per change (`PanelZonesCache`), not once
    /// per pointer event.
    private var panelZones: HoverZones? {
        let frame = panel.frame, screenFrame = screen.frame
        if let cached = zonesCache.zones(panelFrame: frame, screenFrame: screenFrame) { return cached }
        let zones = buildZones(panelFrame: frame, screenFrame: screenFrame)
        zonesCache.store(zones, panelFrame: frame, screenFrame: screenFrame)
        return zones
    }

    private func buildZones(panelFrame frame: CGRect, screenFrame: CGRect) -> HoverZones? {
        guard let geometry = viewModel.hoverGeometry else { return nil }
        return HoverZones(shape: HoverZones.shapeRect(geometry, panelFrame: frame),
                          satellite: satelliteInCanvas().map { HoverZones.screenRect($0, panelFrame: frame) },
                          wings: viewModel.courtesyGeometry.map { HoverZones.shapeRect($0, panelFrame: frame) },
                          screenFrame: screenFrame, band: scene.layout.band,
                          expanded: scene.phase == .open || scene.phase == .peek)
    }

    func pointerMoved(to point: CGPoint) { hover.moved(to: point) }

    /// A file drag moved (`contents` = what is dragged). Sends the machine its drag inputs on zone changes.
    func dragMoved(to point: CGPoint, contents: DragDetector.Contents) {
        guard let entered = hover.dragMoved(to: point), entered else { return }
        viewModel.send(.fileDragEntered(contents.types))
    }

    func dragEnded() {
        hover.resetDrag()
        viewModel.send(.fileDragEnded)
        scene.zones.dragEnded()
    }

    /// The drag ended in a drop on this panel: the next drag starts outside the drag zone. The machine already
    /// had `.filesDropped`, and the armed zone stays until the drop router hands the payload over.
    func dropFinished() {
        hover.resetDrag()
    }

    // MARK: Appearance

    private struct Appearance: Equatable {
        var layout: NotchLayout
        var theme: CrannyTheme
        var ambient: AmbientPalette
    }

    /// What the appearance reads of the display, measured once per display change rather than with every appearance:
    /// the appearance observer runs again with each change of the primary activity (every HUD), and the display has
    /// not changed then. Measured again whenever the frame or the visible frame's top differs (a reconfiguration not
    /// handled yet, the menu bar starting or stopping to auto-hide), and never kept for a display whose metrics come
    /// from the window list (an auto-hidden menu bar's height depends on whether it shows at that moment).
    private struct DisplayMeasure {
        var metrics: NotchMetrics
        var model: String?
        var frame: CGRect
        var visibleTop: CGFloat
        var readsWindowList: Bool

        init(_ screen: NSScreen) {
            metrics = NotchMetrics.measure(screen)
            model = ThemeResolver.displayModelKey(screen)
            frame = screen.frame
            visibleTop = screen.visibleFrame.maxY
            readsWindowList = DisplayCatalog.menuBarAutoHides(on: screen, hasNotch: metrics.hasNotch)
        }

        /// `DisplayCatalog.metrics(for: screen)`, from the measurement while it still holds.
        func metrics(for screen: NSScreen) -> NotchMetrics {
            guard !readsWindowList, screen.frame == frame, screen.visibleFrame.maxY == visibleTop else {
                return DisplayCatalog.metrics(for: screen)
            }
            return metrics
        }
    }

    private static func appearance(screen: NSScreen, display: DisplayMeasure, style: NoNotchStyle, registry: ModuleRegistry,
                                   primary: ActivityID?) -> Appearance {
        let settings = registry.services.settings
        let metrics = display.metrics(for: screen)
        let layout = ThemeResolver.layout(metrics: metrics, displayModel: display.model, style: style,
                                          settings: settings, textSize: settings[CoreSettings.textSize],
                                          density: settings[CoreSettings.density], widgetStyle: settings[CoreSettings.widgetStyle])
        let systemAccent = AccentResolver.systemAccent()
        let theme = ThemeResolver.theme(settings: settings, albumAccent: registry.services.nowPlaying?.palette?.accent,
                                        notchUnit: metrics.unit, isFloatingDisplay: layout.isFloating)
        // DESIGN.md §5.2: the light takes the top activity's palette (album, meeting, timer…).
        let topPalette = primary.flatMap { registry.activity($0)?.activity.palette }
        let ambient = ThemeResolver.ambientPalette(topActivity: topPalette, accent: settings[CoreSettings.accent],
                                                   systemAccent: systemAccent)
        return Appearance(layout: layout, theme: theme, ambient: ambient)
    }

    /// `MiddleLabelMetrics.width` (a display without a notch), measured again only when the label or the notch unit
    /// changed: the label's activity changes far more often than its text (Now Playing's elapsed time).
    private func middleLabelWidth(of label: String?, layout: NotchLayout) -> CGFloat {
        if let memo = labelMemo, memo.label == label, memo.unit == layout.u { return memo.width }
        let width = MiddleLabelMetrics.width(of: label, layout: layout)
        labelMemo = (label, layout.u, width)
        return width
    }

    /// Settings whose change re-arms the idle timers (§4.3 timeouts, per-display toggles).
    private struct IdleTimeoutSettings: Equatable {
        var openTimeout: Double, compactTimeout: Double, hidesHandle: Bool, handleDelay: Double
        var preferences: DisplayPreferences?
    }
    private static func timerSettings(_ settings: SettingsStore, display: DisplayKey) -> IdleTimeoutSettings {
        IdleTimeoutSettings(openTimeout: settings[CoreSettings.openInactivityTimeout],
                      compactTimeout: settings[CoreSettings.compactInactivityTimeout],
                      hidesHandle: settings[CoreSettings.hideHandleWhenIdle], handleDelay: settings[CoreSettings.handleIdleDelay],
                      preferences: settings[CoreSettings.perDisplay][display])
    }

    private func didEmit(_ event: NotchEvent) {
        // DESIGN.md §16: opening tells VoiceOver the layout changed, so focus moves into the panel.
        if case .opened = event, NSWorkspace.shared.isVoiceOverEnabled {
            NSAccessibility.post(element: root, notification: .layoutChanged)
        }
        if event == .closed { keyboard.panelClosed() }
        onEvent(event)
    }

    /// Theme and light apply at once; the frame and layout follow `PanelFramePlan`.
    private func apply(_ appearance: Appearance) {
        if scene.theme != appearance.theme { scene.theme = appearance.theme }
        if scene.ambient != appearance.ambient { scene.ambient = appearance.ambient }
        let screen = self.screen
        let plan = PanelFramePlan(current: panel.frame, canvas: appearance.layout.canvasSize,
                                  layoutChanged: scene.layout != appearance.layout, isClosed: viewModel.state.isClosed) {
            Self.panelFrame(canvas: $0, screen: screen)
        }
        if panel.frame != plan.frame { panel.setFrame(plan.frame, display: true) }
        zonesCache.invalidate()
        layoutIsPending = plan.layout == .pending
        guard plan.layout == .apply else { return }
        pendingTask?.cancel()
        pendingTask = nil
        if scene.layout != appearance.layout { scene.layout = appearance.layout }
        viewModel.refresh()
    }

    /// Applies a pending canvas change once the surface has been closed for `settleDelay` (the close or peek-out
    /// morph has landed). Re-armed by every sync: leaving the closed surface cancels it, the next close starts over.
    private func applyPendingWhenSettled() {
        guard layoutIsPending else { return }
        guard viewModel.state.isClosed else { pendingTask?.cancel(); pendingTask = nil; return }
        guard pendingTask == nil else { return }
        pendingTask = Task { [weak self] in
            try? await Task.sleep(for: Self.settleDelay)
            guard !Task.isCancelled, let self else { return }
            self.pendingTask = nil
            guard self.layoutIsPending, self.viewModel.state.isClosed else { return }
            // Recomputed now: the settings or the display may have changed again meanwhile.
            self.apply(Self.appearance(screen: self.screen, display: self.display, style: self.style, registry: self.registry,
                                       primary: self.scene.primary))
        }
    }

    /// Top-centred on the notch (or the screen), pixel-aligned, clamped inside the screen.
    static func panelFrame(canvas: CGSize, screen: NSScreen) -> CGRect {
        PanelFramePlan.frame(canvas: canvas, screenFrame: screen.frame, leftArea: screen.auxiliaryTopLeftArea,
                             rightArea: screen.auxiliaryTopRightArea)
    }

    // MARK: Hit area (canvas: top-left origin; root view: bottom-left)

    private func satelliteInCanvas() -> CGRect? {
        viewModel.satelliteFrame(in: CGRect(origin: .zero, size: root.bounds.size))
    }

    /// The enlarged drop zone while a file drag is in progress: the drag zone clipped to the canvas. Only where a drop
    /// can land (an open panel's widget zones, or a Tray to keep it), so menu-bar clicks are never blocked for nothing.
    private func dropZoneInCanvas() -> CGRect? {
        let state = viewModel.state
        let canTake = state.isOpen || registry.services.tray != nil
        guard (state.fileDrag != nil && canTake) || state.isCatching, let zones = hoverZones else { return nil }
        let frame = panel.frame
        let zone = zones.dragZone.intersection(frame)
        guard !zone.isNull, !zone.isEmpty else { return nil }
        return CGRect(x: zone.minX - frame.minX, y: frame.maxY - zone.maxY, width: zone.width, height: zone.height)
    }

    /// The root view's hit area: the shape, plus the satellite and the drop zone while they show.
    private func interactiveRect() -> CGRect {
        let g = scene.geometry
        let size = root.bounds.size
        func flipped(_ r: CGRect) -> CGRect { CGRect(x: r.minX, y: size.height - r.maxY, width: r.width, height: r.height) }
        var rect = flipped(CGRect(x: size.width / 2 - g.outerWidth / 2, y: 0, width: g.outerWidth, height: g.bottom))
        if let satellite = satelliteInCanvas() { rect = rect.union(flipped(satellite)) }
        if let zone = chrome.dropZone { rect = rect.union(flipped(zone)) }
        return rect
    }
}
