// CrannyEffects/Layer/AmbientMetalView.swift — the dedicated Metal layer of the ambient light.
//
// Why: drawing the light with a SwiftUI shader re-renders the panel's view tree on every frame, which cost
// 5–10 % CPU at 30 fps (ARCHITECTURE.md §10.1, issue 1). This view owns a `CAMetalLayer` and its own frame loop,
// so SwiftUI only hears about the light when an input changes (palette, energy, fill, reveal, budget).
//
// Energy rules (ARCHITECTURE.md §9.2): frames come from a `Task.sleep` loop paced at the budget's interval
// (30 fps on AC, 20 on battery); there is no loop while the budget is paused (closed, occluded, full screen),
// while the window is occluded or gone, or while the view has no size. A paused layer keeps its last frame and
// redraws only when an input changes: at most once per main-queue turn, after that turn's layout (a resize frame in
// the same update already shows the change), and not while the window is occluded (it redraws when it is revealed).
// On resume time continues from the last frame (nothing jumps). The view holds its `AmbientRenderer` only while it
// is in a window (AmbientRenderer.swift explains when the GPU is let go).
//
// The CAMetalLayer belongs to a subview that covers only the lit band at the bottom of the light, never its clear top
// (AmbientDrawableLayout.swift); this view clips it.
//
// Resizing (the open and close morph, when callers frame the light to the shape's current bounds): every layout
// pass that changes the size draws one frame at the new size and presents it inside the same Core Animation
// transaction, so the light is never shown stretched or a frame behind the shape. Meanwhile the drawable only grows,
// in steps, instead of being reallocated on every frame; the next frame drawn at rest returns it to the band's exact
// size (presented with the transaction too, since its frame changes).
import AppKit
import CoreGraphics
import CrannyCore
import Foundation
import Metal
import QuartzCore
import SwiftUI

/// SwiftUI host of `AmbientMetalNSView`. Used by `AmbientFieldView` on the `.layer` path.
struct AmbientMetalLayer: NSViewRepresentable {
    var state: AmbientLayerState

    func makeNSView(context: Context) -> AmbientMetalNSView {
        let view = AmbientMetalNSView()
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
    /// The renderer of the GPU this view draws with; held only while the view is in a window.
    private(set) var renderer: AmbientRenderer?
    private let drawableView = AmbientDrawableView()
    /// The layer the frames are presented in (tests).
    var metalLayer: CAMetalLayer { drawableView.metalLayer }
    /// The drawable's size and place now; nil until the view first has a size (tests).
    private(set) var drawableLayout: AmbientDrawableLayout?
    /// The drawable's frame or size changed: the next frame is presented with the Core Animation transaction, so the
    /// new frame and the new pixels appear together.
    private var needsSynchronizedFrame = false

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
    /// When the last frame was drawn: a loop tick right after a resize frame is skipped (one draw per frame at most).
    private var lastDrawn: ContinuousClock.Instant?
    /// A paused layer's pending redraw of its latest input (one per main-queue turn); tests await it.
    private(set) var pausedRedraw: Task<Void, Never>?
    /// An input changed after the last frame drawn (any frame shows the latest state).
    private var hasUndrawnInput = false
    /// Tests only: their windows are never ordered in, so the window server reports them occluded.
    var treatsWindowAsVisible = false
    /// Whether the frame loop runs now (tests).
    var isRunning: Bool { loop != nil }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layerContentsRedrawPolicy = .never
        clipsToBounds = true                         // a resizing drawable may reach past the bounds (never drawn)
        setAccessibilityElement(false)
        addSubview(drawableView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    deinit { loop?.cancel() }

    override var isOpaque: Bool { false }
    /// Light never takes a click (the panel's per-pixel pass-through relies on it).
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    // MARK: - Window, size, scale

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        let center = NotificationCenter.default
        if let window {
            center.removeObserver(self, name: NSWindow.didChangeOcclusionStateNotification, object: window)
            center.removeObserver(self, name: NSWindow.didChangeScreenNotification, object: window)
        }
        if let newWindow {
            center.addObserver(self, selector: #selector(occlusionDidChange(_:)),
                               name: NSWindow.didChangeOcclusionStateNotification, object: newWindow)
            center.addObserver(self, selector: #selector(screenDidChange(_:)),
                               name: NSWindow.didChangeScreenNotification, object: newWindow)
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateRenderer()
        updateDrawableSize()
        updateLoop(drawsFirstFrame: false)
        drawNow()
    }

    override func setFrameSize(_ newSize: NSSize) {
        let changed = newSize != frame.size
        super.setFrameSize(newSize)
        guard changed else { return }
        updateDrawableSize(resizing: true)
        updateLoop(drawsFirstFrame: false)
        draw(at: Date(), running: loop != nil, synchronized: true)     // in step with the new bounds
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
        updateLoop(drawsFirstFrame: false)
        if isWindowVisible { drawNow() }
    }

    @objc private func screenDidChange(_ notification: Notification) {
        updateRenderer()
        drawNow()
    }

    /// Takes the renderer of the GPU for this window's display, or lets it go when the view leaves its window.
    private func updateRenderer() {
        guard let window else {
            renderer = nil
            metalLayer.device = nil                  // the layer would otherwise keep the GPU (and its drawables)
            return
        }
        let display = (window.screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)
            .map { CGDirectDisplayID($0.uint32Value) }
        let next = AmbientRenderer.renderer(forDisplay: display)
        guard next !== renderer else { return }
        renderer = next
        metalLayer.device = next?.device
    }

    /// Pixels per point of the drawable (1 for the soft aurora and halo, the display's scale otherwise).
    private var scale: CGFloat {
        AmbientRenderer.renderScale(for: state?.effect ?? .motes, displayScale: window?.backingScaleFactor ?? 2)
    }

    /// Lays the drawable out for the current bounds, scale and effect: exactly the lit band, or while `resizing` at
    /// least that, grown in steps (AmbientDrawableLayout.swift). A new frame or size is presented with the next frame.
    private func updateDrawableSize(resizing: Bool = false) {
        let scale = scale
        if metalLayer.contentsScale != scale { metalLayer.contentsScale = scale }
        let litTop = AmbientRenderer.litTop(state?.effect ?? .motes, height: bounds.height, energy: state?.energy ?? 0)
        guard let next = AmbientDrawableLayout(bounds: bounds.size, scale: scale, litTop: litTop,
                                               growingFrom: resizing ? drawableLayout?.pixels : nil),
              next != drawableLayout else { return }
        let previous = drawableLayout
        drawableLayout = next
        guard next.frame != previous?.frame || next.pixels != previous?.pixels else { return }
        drawableView.frame = next.frame
        metalLayer.drawableSize = next.pixels
        needsSynchronizedFrame = true
    }

    private var isWindowVisible: Bool {
        guard let window else { return false }
        return treatsWindowAsVisible || window.occlusionState.contains(.visible) || EffectsQA.keepsRunning
    }

    private var hasSize: Bool { bounds.width >= 1 && bounds.height >= 1 }

    // MARK: - Frame loop

    /// Stops the loop for good and lets the renderer go (the view is being dismantled).
    func stop() {
        loop?.cancel()
        loop = nil
        loopInterval = nil
        pausedRedraw?.cancel()
        pausedRedraw = nil
        renderer = nil
        metalLayer.device = nil
    }

    private func stateDidChange() {
        updateLoop()                                 // draws the first frame itself when it starts the loop
        // A new effect moved the drawable: show its pixels with its new frame now, not a loop interval later.
        if needsSynchronizedFrame { drawNow(); return }
        // A running loop picks the change up on its next frame; a paused layer redraws (fill and colour animations
        // stay visible while time stands still, e.g. the drain on close).
        if loop == nil { schedulePausedRedraw() }
    }

    /// The paused layer's redraw of its latest input, at the end of this main-queue turn: after the turn's layout, so
    /// an input that changes together with the size (the fill rising during the open morph) costs one frame, the
    /// resize frame, not two. Once per turn however many inputs change; skipped while the window is occluded
    /// (`occlusionDidChange` draws the latest state when it is revealed).
    private func schedulePausedRedraw() {
        hasUndrawnInput = true
        guard pausedRedraw == nil else { return }
        pausedRedraw = Task { [weak self] in
            guard let self, !Task.isCancelled else { return }
            self.pausedRedraw = nil
            // Not when a frame (a resize frame) has shown it since, nor while a loop draws or nobody can see it.
            guard self.hasUndrawnInput, self.loop == nil, self.isWindowVisible else { return }
            self.drawNow()
        }
    }

    /// The interval the loop should run at now, or nil when it should not run.
    private var wantedInterval: Double? {
        guard let interval = state?.interval, interval > 0, renderer != nil, isWindowVisible, hasSize,
              !isHiddenOrHasHiddenAncestor else { return nil }
        return interval
    }

    /// Starts, restarts or stops the frame loop to match `wantedInterval`. A loop that starts draws its first frame at
    /// once unless the caller is about to draw one itself (`drawsFirstFrame: false`): one frame per event at most.
    private func updateLoop(drawsFirstFrame: Bool = true) {
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
                deadline = FramePacing.nextDeadline(after: deadline, now: clock.now, interval: interval)
                do {
                    try await Task.sleep(until: deadline, tolerance: .seconds(interval / 8), clock: clock)
                } catch {
                    return                                                   // cancelled: paused or gone
                }
                guard let self else { return }
                // During a resize the layout already draws every display frame; the loop adds nothing then.
                if let last = self.lastDrawn, clock.now - last < .seconds(interval / 2) { continue }
                self.draw(at: Date(), running: true)
            }
        }
        if drawsFirstFrame { draw(at: Date(), running: true) }             // the first frame without waiting
    }

    private func drawNow() { draw(at: Date(), running: loop != nil) }

    /// Draws one frame. `synchronized`: a resize frame, presented with the new bounds (its drawable may be larger than
    /// the band). Any other frame first returns the drawable to the band's exact size.
    private func draw(at date: Date, running: Bool, synchronized: Bool = false) {
        guard let state, let renderer, hasSize, window != nil else { return }
        if !synchronized { updateDrawableSize() }
        guard let layout = drawableLayout else { return }
        let time: Double
        if running || lastTime == nil {
            let t = (EffectTiming.ambientTime(date) + timeOffset).truncatingRemainder(dividingBy: 3600)
            time = t < 0 ? t + 3600 : t
        } else {
            time = lastTime ?? state.restingTime
        }
        lastTime = time
        let uniforms = AmbientUniforms(state: state, size: bounds.size, scale: scale, time: time, date: date,
                                       rowOffset: layout.offset)
        if renderer.draw(state.effect, uniforms: uniforms, in: metalLayer, region: layout.hasSlack ? layout.region : nil,
                         synchronized: synchronized || needsSynchronizedFrame) {
            needsSynchronizedFrame = false
            hasUndrawnInput = false
            framesDrawn += 1
            lastDrawn = ContinuousClock.now
        }
    }
}

// MARK: - Previews

#Preview("Metal layer · aurora at 30 fps") {
    AmbientMetalLayer(state: AmbientLayerState(effect: .aurora, glows: AmbientPalette.afterglow.glows, energy: 0,
                                               level: .vivid, fill: 1, reveal: nil, rippleStart: nil,
                                               halo: .ambient, interval: 1.0 / 30, restingTime: 7.3))
    .frame(width: 656, height: 170)
    .background(.black)
    .crannyThemeRoot(CrannyTheme())
}
