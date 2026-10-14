// CrannyAppShell/Overlay/NotchPanelController.swift — one display's panel (ARCHITECTURE.md §5.3).
// A fixed-size, non-activating panel at level 26, top-centred on the notch (screen centre without one);
// every morph is SwiftUI inside it. WP0 skeleton; WP13 adds drops, scrolls, calibration and full screen.
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
    private(set) var screen: NSScreen
    private(set) var style: NoNotchStyle
    private let registry: ModuleRegistry
    private var pointerInside = false
    private var keyMonitor: Any?
    private var keyObservers: [any NSObjectProtocol] = []
    private var appearanceToken: ObservationToken?
    /// A layout change that arrived while the panel was not idle (applied after the next close).
    private var pendingAppearance: Appearance?
    /// Every event of this display, forwarded by the coordinator to `NotchControl` observers.
    var onEvent: (NotchEvent) -> Void = { _ in }

    init(screen: NSScreen, key: DisplayKey, style: NoNotchStyle, registry: ModuleRegistry) {
        self.screen = screen; self.key = key; self.style = style; self.registry = registry
        let appearance = Self.appearance(screen: screen, style: style, registry: registry)
        scene = NotchSceneModel(layout: appearance.layout, theme: appearance.theme)
        scene.ambient = appearance.ambient
        scene.context.display = key
        viewModel = NotchViewModel(scene: scene, registry: registry)

        let frame = Self.panelFrame(canvas: appearance.layout.canvasSize, screen: screen)
        panel = NotchPanel(frame: frame)
        root = NotchRootView(frame: CGRect(origin: .zero, size: frame.size))
        let host = NotchHostingView(rootView: NotchCanvasView(model: scene, registry: registry, actions: viewModel.actions))
        host.sizingOptions = []
        host.safeAreaRegions = []                 // no 32–38 pt jump on notched displays
        host.frame = root.bounds
        host.autoresizingMask = [.width, .height]
        root.addSubview(host)
        panel.contentView = root
        root.interactiveRect = { [weak self] in self?.interactiveRect() ?? .zero }

        viewModel.makeKey = { [weak self] in self?.panel.makeKey() }
        viewModel.relinquishKey = { [weak self] in self?.relinquishKeyIfNeeded() }
        viewModel.onEvent = { [weak self] event in self?.didEmit(event) }
        viewModel.refresh()

        // Esc closes and hands focus back (the panel only receives keys while it is key).
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.panel, event.keyCode == 53 else { return event }   // kVK_Escape
            self.viewModel.send(.escape)
            return nil
        }
        // §4.4/§4.5: while the panel is key (hot key, a clicked text field) leaving it never closes it.
        for (name, isKey) in [(NSWindow.didBecomeKeyNotification, true), (NSWindow.didResignKeyNotification, false)] {
            keyObservers.append(NotificationCenter.default.addObserver(forName: name, object: panel, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.viewModel.send(.hold(NotchMachineState.typingHold, isKey)) }   // queue: .main
            })
        }
        // Theme, layout and light follow the settings live (observed, no polling).
        appearanceToken = observe({ [weak self] in self.map { Self.appearance(screen: $0.screen, style: $0.style, registry: $0.registry) } }) {
            [weak self] appearance in
            if let appearance { self?.apply(appearance) }
        }
        panel.orderFrontRegardless()                // never activates the app
    }

    /// Geometry changes apply only while closed (the canvas is resized between morphs, never during one).
    func update(screen: NSScreen, style: NoNotchStyle) {
        self.screen = screen; self.style = style
        apply(Self.appearance(screen: screen, style: style, registry: registry))
    }

    func close() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        for observer in keyObservers { NotificationCenter.default.removeObserver(observer) }
        keyObservers.removeAll()
        appearanceToken?.cancel()
        relinquishKeyIfNeeded()
        panel.orderOut(nil)
        panel.close()
    }

    // MARK: Pointer

    /// Screen coordinates (AppKit, bottom-left origin) of the shape as currently drawn.
    var shapeFrameOnScreen: CGRect {
        let g = scene.geometry
        return CGRect(x: panel.frame.midX - g.outerWidth / 2, y: panel.frame.maxY - g.bottom,
                      width: g.outerWidth, height: g.height)
    }

    /// Entry zone (closed) = shape + 4 pt; exit zone (open/peek) = shape + 14 pt. Both reach above the
    /// screen's top edge, because the pointer's y can equal `frame.maxY` (R1 §2.5).
    func zoneContains(_ point: CGPoint) -> Bool {
        let expanded = scene.phase == .open || scene.phase == .peek
        let inflation = expanded ? HoverIntent.exitInflation : HoverIntent.entryInflation
        var zone = shapeFrameOnScreen.insetBy(dx: -inflation, dy: -inflation)
        zone.size.height = screen.frame.maxY + 1 - zone.minY
        return zone.contains(point)
    }

    func pointerMoved(to point: CGPoint) {
        let inside = zoneContains(point)
        guard inside != pointerInside else { return }
        pointerInside = inside
        viewModel.send(inside ? .pointerEntered : .pointerLeft)
    }

    // MARK: Private

    private struct Appearance: Equatable {
        var layout: NotchLayout
        var theme: CrannyTheme
        var ambient: AmbientPalette
    }

    private static func appearance(screen: NSScreen, style: NoNotchStyle, registry: ModuleRegistry) -> Appearance {
        let settings = registry.services.settings
        let metrics = NotchMetrics.measure(screen)
        let layout = ThemeResolver.layout(metrics: metrics, displayModel: ThemeResolver.displayModelKey(screen), style: style,
                                          settings: settings, textSize: settings[CoreSettings.textSize],
                                          density: settings[CoreSettings.density], widgetStyle: settings[CoreSettings.widgetStyle])
        let theme = ThemeResolver.theme(settings: settings, albumAccent: registry.services.nowPlaying?.palette?.accent,
                                        notchUnit: metrics.unit, isFloatingDisplay: layout.isFloating)
        let ambient = ThemeResolver.ambientPalette(topActivity: nil, accent: settings[CoreSettings.accent],
                                                   systemAccent: AccentResolver.systemAccent())
        return Appearance(layout: layout, theme: theme, ambient: ambient)
    }

    private func didEmit(_ event: NotchEvent) {
        if event == .closed, let pendingAppearance {
            // Let the close animation land before the canvas may change size.
            Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(600))
                if let self, self.scene.phase == .idle || self.scene.phase == .hidden { self.apply(pendingAppearance) }
            }
        }
        onEvent(event)
    }

    private func apply(_ appearance: Appearance) {
        if scene.theme != appearance.theme { scene.theme = appearance.theme }
        if scene.ambient != appearance.ambient { scene.ambient = appearance.ambient }
        guard scene.layout != appearance.layout else { pendingAppearance = nil; return }
        guard scene.phase == .idle || scene.phase == .hidden else { pendingAppearance = appearance; return }
        pendingAppearance = nil
        scene.layout = appearance.layout
        let frame = Self.panelFrame(canvas: appearance.layout.canvasSize, screen: screen)
        if panel.frame != frame { panel.setFrame(frame, display: true) }
        viewModel.refresh()
    }

    /// Top-centred on the notch (or the screen), pixel-aligned, clamped inside the screen.
    private static func panelFrame(canvas: CGSize, screen: NSScreen) -> CGRect {
        let f = screen.frame
        var midX = f.midX
        if let l = screen.auxiliaryTopLeftArea, let r = screen.auxiliaryTopRightArea, l.width > 0, r.width > 0 {
            midX = f.minX + (f.width + l.width - r.width) / 2               // centre of the camera housing
        }
        var frame = CGRect(x: midX - canvas.width / 2, y: f.maxY - canvas.height, width: canvas.width, height: canvas.height)
        frame.origin.x = min(max(frame.minX, f.minX), f.maxX - frame.width)
        return frame.integral
    }

    /// The root view's hit area: the shape (bottom-left coordinates of the canvas).
    private func interactiveRect() -> CGRect {
        let g = scene.geometry
        let size = root.bounds.size
        return CGRect(x: size.width / 2 - g.outerWidth / 2, y: size.height - g.bottom, width: g.outerWidth, height: g.bottom)
    }

    /// Hand key status back to the previously focused window (R1 §3.5).
    private func relinquishKeyIfNeeded() {
        guard panel.isKeyWindow else { return }
        panel.orderOut(nil)
        panel.orderFrontRegardless()
    }
}
