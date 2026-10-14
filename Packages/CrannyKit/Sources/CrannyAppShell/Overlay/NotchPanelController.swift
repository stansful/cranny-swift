// CrannyAppShell/Overlay/NotchPanelController.swift — one display's panel (ARCHITECTURE.md §5.3).
// A fixed-size, non-activating panel at level 26, top-centred on the notch (screen centre without one); every
// morph is SwiftUI inside it. The controller wires the panel to its view model and input routers (hover zones,
// swipes, keys, drops, key focus) and keeps theme, layout and light in step with the settings by observation.
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
    private let hover = HoverTracker()
    private let focus: FocusManager
    private let keyboard: KeyboardRouter
    private let gestures: GestureRouter
    private let drops: DropRouter
    private var tokens: [ObservationToken] = []
    /// A layout change that arrived while the panel was not idle (applied after the next close).
    private var pendingAppearance: Appearance?
    /// Every event of this display, forwarded by the coordinator to `NotchControl` observers.
    var onEvent: (NotchEvent) -> Void = { _ in }
    /// A drop finished on this panel (the coordinator resets its drag detector).
    var onDropFinished: () -> Void = {}

    init(screen: NSScreen, key: DisplayKey, style: NoNotchStyle, registry: ModuleRegistry) {
        self.screen = screen; self.key = key; self.style = style; self.registry = registry
        let appearance = Self.appearance(screen: screen, style: style, registry: registry, primary: nil)
        scene = NotchSceneModel(layout: appearance.layout, theme: appearance.theme)
        scene.ambient = appearance.ambient
        scene.context.display = key
        viewModel = NotchViewModel(scene: scene, registry: registry)

        let frame = Self.panelFrame(canvas: appearance.layout.canvasSize, screen: screen)
        panel = NotchPanel(frame: frame)
        root = NotchRootView(frame: CGRect(origin: .zero, size: frame.size))
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
        drops.onDropFinished = { [weak self] in self?.onDropFinished() }
        focus.start()
        keyboard.start()
        // Theme, layout and light follow the settings and the primary activity's palette (observed, no polling).
        tokens.append(observe({ [weak self] in
            self.map { Self.appearance(screen: $0.screen, style: $0.style, registry: $0.registry, primary: $0.scene.primary) }
        }) { [weak self] appearance in
            if let appearance { self?.apply(appearance) }
        })
        // Timeouts and per-display toggles re-arm the machine's idle timers.
        let settings = registry.services.settings
        tokens.append(observe({ [key] in Self.timerSettings(settings, display: key) }) { [weak self] _ in
            self?.viewModel.send(.configChanged)
        })
        // The drop zone (and with it the hit area) follows the drag state.
        viewModel.didSync = { [weak self] in
            guard let self else { return }
            let zone = self.dropZoneInCanvas()
            if self.chrome.dropZone != zone { self.chrome.dropZone = zone }
        }
    }

    /// Geometry changes apply only while closed (the canvas is resized between morphs, never during one).
    func update(screen: NSScreen, style: NoNotchStyle) {
        self.screen = screen; self.style = style
        apply(Self.appearance(screen: screen, style: style, registry: registry, primary: scene.primary))
        if !panel.isVisible { panel.orderFrontRegardless() }
    }

    func close() {
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

    /// The hover zones in screen coordinates, or nil while hidden (§4.3, DESIGN.md §3.6).
    var hoverZones: HoverZones? {
        guard let geometry = viewModel.hoverGeometry else { return nil }
        let frame = panel.frame
        return HoverZones(shape: HoverZones.shapeRect(geometry, panelFrame: frame),
                          satellite: satelliteInCanvas().map { HoverZones.screenRect($0, panelFrame: frame) },
                          wings: viewModel.courtesyGeometry.map { HoverZones.shapeRect($0, panelFrame: frame) },
                          screenFrame: screen.frame, band: scene.layout.band,
                          expanded: scene.phase == .open || scene.phase == .peek)
    }

    func zoneContains(_ point: CGPoint) -> Bool { hoverZones?.contains(point) ?? false }

    func pointerMoved(to point: CGPoint) {
        for input in hover.update(point, zones: hoverZones) { viewModel.send(input) }
    }

    /// A file drag moved (`contents` = what is dragged). Sends the machine its drag inputs on zone changes.
    func dragMoved(to point: CGPoint, contents: DragDetector.Contents) {
        guard let entered = hover.updateDrag(point, zones: hoverZones), entered else { return }
        viewModel.send(.fileDragEntered(contents.types))
    }

    func dragEnded() {
        hover.resetDrag()
        viewModel.send(.fileDragEnded)
        scene.zones.dragEnded()
    }

    // MARK: Appearance

    private struct Appearance: Equatable {
        var layout: NotchLayout
        var theme: CrannyTheme
        var ambient: AmbientPalette
    }

    private static func appearance(screen: NSScreen, style: NoNotchStyle, registry: ModuleRegistry,
                                   primary: ActivityID?) -> Appearance {
        let settings = registry.services.settings
        let metrics = DisplayCatalog.metrics(for: screen)
        let layout = ThemeResolver.layout(metrics: metrics, displayModel: ThemeResolver.displayModelKey(screen), style: style,
                                          settings: settings, textSize: settings[CoreSettings.textSize],
                                          density: settings[CoreSettings.density], widgetStyle: settings[CoreSettings.widgetStyle])
        let theme = ThemeResolver.theme(settings: settings, albumAccent: registry.services.nowPlaying?.palette?.accent,
                                        notchUnit: metrics.unit, isFloatingDisplay: layout.isFloating)
        // DESIGN.md §5.2: the light takes the top activity's palette (album, meeting, timer…).
        let topPalette = primary.flatMap { registry.activity($0)?.activity.palette }
        let ambient = ThemeResolver.ambientPalette(topActivity: topPalette, accent: settings[CoreSettings.accent],
                                                   systemAccent: AccentResolver.systemAccent())
        return Appearance(layout: layout, theme: theme, ambient: ambient)
    }

    /// Settings whose change re-arms the idle timers (§4.3 timeouts, per-display toggles).
    private struct TimerSettings: Equatable {
        var openTimeout: Double, compactTimeout: Double, hidesHandle: Bool, handleDelay: Double
        var preferences: DisplayPreferences?
    }
    private static func timerSettings(_ settings: SettingsStore, display: DisplayKey) -> TimerSettings {
        TimerSettings(openTimeout: settings[CoreSettings.openInactivityTimeout],
                      compactTimeout: settings[CoreSettings.compactInactivityTimeout],
                      hidesHandle: settings[CoreSettings.hideHandleWhenIdle], handleDelay: settings[CoreSettings.handleIdleDelay],
                      preferences: settings[CoreSettings.perDisplay][display])
    }

    private func didEmit(_ event: NotchEvent) {
        if event == .closed {
            keyboard.panelClosed()
            if let pendingAppearance {
                // Let the close animation land before the canvas may change size.
                Task { [weak self] in
                    try? await Task.sleep(for: .milliseconds(600))
                    if let self, self.scene.phase == .idle || self.scene.phase == .hidden || self.scene.phase == .compact {
                        self.apply(pendingAppearance)
                    }
                }
            }
        }
        onEvent(event)
    }

    private func apply(_ appearance: Appearance) {
        if scene.theme != appearance.theme { scene.theme = appearance.theme }
        if scene.ambient != appearance.ambient { scene.ambient = appearance.ambient }
        guard scene.layout != appearance.layout else { pendingAppearance = nil; return }
        guard viewModel.state.isClosed else { pendingAppearance = appearance; return }
        pendingAppearance = nil
        scene.layout = appearance.layout
        let frame = Self.panelFrame(canvas: appearance.layout.canvasSize, screen: screen)
        if panel.frame != frame { panel.setFrame(frame, display: true) }
        viewModel.refresh()
    }

    /// Top-centred on the notch (or the screen), pixel-aligned, clamped inside the screen.
    static func panelFrame(canvas: CGSize, screen: NSScreen) -> CGRect {
        let f = screen.frame
        var midX = f.midX
        if let l = screen.auxiliaryTopLeftArea, let r = screen.auxiliaryTopRightArea, l.width > 0, r.width > 0 {
            midX = f.minX + (f.width + l.width - r.width) / 2               // centre of the camera housing
        }
        var frame = CGRect(x: midX - canvas.width / 2, y: f.maxY - canvas.height, width: canvas.width, height: canvas.height)
        frame.origin.x = min(max(frame.minX, f.minX), f.maxX - frame.width)
        return frame.integral
    }

    // MARK: Hit area (canvas: top-left origin; root view: bottom-left)

    private func satelliteInCanvas() -> CGRect? {
        guard scene.phase == .compact, scene.satellite != nil else { return nil }
        return scene.layout.satelliteFrame(beside: scene.layout.compact(scene.primarySlot), in: CGRect(origin: .zero, size: root.bounds.size))
    }

    /// The enlarged drop zone while a file drag is in progress: the drag zone clipped to the canvas.
    private func dropZoneInCanvas() -> CGRect? {
        guard viewModel.state.fileDrag != nil || viewModel.state.isCatching, let zones = hoverZones else { return nil }
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
