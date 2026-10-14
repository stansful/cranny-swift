// CrannyEffects/Layer/AmbientMetalView.swift — the dedicated Metal layer of the ambient light.
//
// Why: drawing the light with a SwiftUI shader re-renders the panel's view tree on every frame, which cost
// 5–10 % CPU at 30 fps (ARCHITECTURE.md §10.1, issue 1). This view owns a `CAMetalLayer` and its own frame loop,
// so SwiftUI only hears about the light when an input changes (palette, energy, fill, reveal, budget).
//
// Energy rules (ARCHITECTURE.md §9.2): frames come from a `Task.sleep` loop paced at the budget's interval
// (30 fps on AC, 20 on battery); there is no loop while the budget is paused (closed, occluded, full screen),
// while the window is occluded or gone, or while the view has no size. A paused layer keeps its last frame and
// redraws only when an input changes, and on resume time continues from that frame (nothing jumps).
import AppKit
import CrannyCore
import Foundation
import QuartzCore
import SwiftUI

/// SwiftUI host of `AmbientMetalNSView`. Used by `AmbientFieldView` on the `.layer` path.
struct AmbientMetalLayer: NSViewRepresentable {
    var state: AmbientLayerState
    let renderer: AmbientRenderer

    func makeNSView(context: Context) -> AmbientMetalNSView {
        let view = AmbientMetalNSView(renderer: renderer)
        view.state = state
        return view
    }

    func updateNSView(_ view: AmbientMetalNSView, context: Context) {
        view.state = state
    }

    static func dismantleNSView(_ view: AmbientMetalNSView, coordinator: ()) {
        view.stop()
    }
}

final class AmbientMetalNSView: NSView {
    private let renderer: AmbientRenderer
    private let metalLayer = CAMetalLayer()

    /// Set by SwiftUI on every update.
    var state: AmbientLayerState? {
        didSet {
            guard state != oldValue else { return }
            if state?.effect != oldValue?.effect { updateDrawableSize() }
            stateDidChange()
        }
    }

    // The frame loop. `nonisolated(unsafe)` only so `deinit` can cancel it; it is otherwise main-actor state.
    nonisolated(unsafe) private var loop: Task<Void, Never>?
    private var loopInterval: Double?
    /// Shader time of the last frame drawn, and the offset that makes a resumed loop continue from it.
    private var lastTime: Double?
    private var timeOffset: Double = 0
    /// Frames drawn (tests and diagnostics).
    private(set) var framesDrawn = 0
    /// Whether the frame loop runs now (tests).
    var isRunning: Bool { loop != nil }

    init(renderer: AmbientRenderer) {
        self.renderer = renderer
        super.init(frame: .zero)
        metalLayer.device = renderer.device
        metalLayer.pixelFormat = AmbientRenderer.pixelFormat
        metalLayer.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
        metalLayer.framebufferOnly = true
        metalLayer.isOpaque = false
        metalLayer.presentsWithTransaction = false
        metalLayer.needsDisplayOnBoundsChange = false
        wantsLayer = true
        layerContentsRedrawPolicy = .never
        setAccessibilityElement(false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    deinit { loop?.cancel() }

    override func makeBackingLayer() -> CALayer { metalLayer }
    override var isOpaque: Bool { false }
    /// Light never takes a click (the panel's per-pixel pass-through relies on it).
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    // MARK: - Window, size, scale

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        let center = NotificationCenter.default
        if let window {
            center.removeObserver(self, name: NSWindow.didChangeOcclusionStateNotification, object: window)
        }
        if let newWindow {
            center.addObserver(self, selector: #selector(occlusionDidChange(_:)),
                               name: NSWindow.didChangeOcclusionStateNotification, object: newWindow)
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateDrawableSize()
        updateLoop()
        drawNow()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateDrawableSize()
        updateLoop()
        drawNow()                                    // never show a stretched frame while SwiftUI resizes us
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateDrawableSize()
        drawNow()
    }

    override func viewDidHide() {
        super.viewDidHide()
        updateLoop()
    }

    override func viewDidUnhide() {
        super.viewDidUnhide()
        updateLoop()
    }

    @objc private func occlusionDidChange(_ notification: Notification) {
        updateLoop()
        if isWindowVisible { drawNow() }
    }

    /// Pixels per point of the drawable (1 for the soft aurora and halo, the display's scale otherwise).
    private var scale: CGFloat {
        AmbientRenderer.renderScale(for: state?.effect ?? .motes, displayScale: window?.backingScaleFactor ?? 2)
    }

    private func updateDrawableSize() {
        let scale = scale
        metalLayer.contentsScale = scale
        let size = CGSize(width: (bounds.width * scale).rounded(), height: (bounds.height * scale).rounded())
        if size.width >= 1, size.height >= 1, metalLayer.drawableSize != size { metalLayer.drawableSize = size }
    }

    private var isWindowVisible: Bool {
        guard let window else { return false }
        return window.occlusionState.contains(.visible) || EffectsQA.keepsRunning
    }

    private var hasSize: Bool { bounds.width >= 1 && bounds.height >= 1 }

    // MARK: - Frame loop

    /// Stops the loop for good (the view is being dismantled).
    func stop() {
        loop?.cancel()
        loop = nil
        loopInterval = nil
    }

    private func stateDidChange() {
        updateLoop()                                 // draws the first frame itself when it starts the loop
        // A running loop picks the change up on its next frame; a paused layer redraws now (fill and colour
        // animations stay visible while time stands still, e.g. the drain on close).
        if loop == nil { drawNow() }
    }

    /// The interval the loop should run at now, or nil when it should not run.
    private var wantedInterval: Double? {
        guard let interval = state?.interval, interval > 0, isWindowVisible, hasSize, !isHiddenOrHasHiddenAncestor
        else { return nil }
        return interval
    }

    private func updateLoop() {
        let interval = wantedInterval
        guard interval != loopInterval || (interval != nil && loop == nil) else { return }
        loop?.cancel()
        loop = nil
        loopInterval = interval
        guard let interval else { return }
        // Resume where the last frame left off instead of jumping to the wall clock.
        if let lastTime { timeOffset = lastTime - EffectTiming.ambientTime(Date()) }
        loop = Task { [weak self] in
            let clock = ContinuousClock()
            var deadline = clock.now
            while !Task.isCancelled {
                deadline = EffectTiming.nextDeadline(after: deadline, now: clock.now, interval: interval)
                do {
                    try await Task.sleep(until: deadline, tolerance: .seconds(interval / 8), clock: clock)
                } catch {
                    return                                                   // cancelled: paused or gone
                }
                guard let self else { return }
                self.draw(at: Date(), running: true)
            }
        }
        draw(at: Date(), running: true)                                     // the first frame without waiting
    }

    private func drawNow() { draw(at: Date(), running: loop != nil) }

    private func draw(at date: Date, running: Bool) {
        guard let state, hasSize, window != nil else { return }
        let time: Double
        if running || lastTime == nil {
            let t = (EffectTiming.ambientTime(date) + timeOffset).truncatingRemainder(dividingBy: 3600)
            time = t < 0 ? t + 3600 : t
        } else {
            time = lastTime ?? state.restingTime
        }
        lastTime = time
        let uniforms = AmbientUniforms(state: state, size: bounds.size, scale: scale, time: time, date: date)
        if renderer.draw(state.effect, uniforms: uniforms, in: metalLayer) { framesDrawn += 1 }
    }
}

// MARK: - Previews

#Preview("Metal layer · aurora at 30 fps") {
    Group {
        if let renderer = AmbientRenderer.shared {
            AmbientMetalLayer(state: AmbientLayerState(effect: .aurora, glows: AmbientPalette.afterglow.glows, energy: 0,
                                                       level: .vivid, fill: 1, reveal: nil, rippleStart: nil,
                                                       halo: .ambient, interval: 1.0 / 30, restingTime: 7.3),
                              renderer: renderer)
        }
    }
    .frame(width: 656, height: 170)
    .background(.black)
    .crannyThemeRoot(CrannyTheme())
}
