// CrannyEffects/Layer/AmbientMetalView.swift — the dedicated Metal layer of the ambient light.
//
// Why: drawing the light with a SwiftUI shader re-renders the panel's view tree on every frame, which cost
// 5–10 % CPU at 30 fps (ARCHITECTURE.md §10.1, issue 1). This view owns a `CAMetalLayer` and its own frame loop,
// so SwiftUI only hears about the light when an input changes (palette, fill, reveal, budget). Live audio energy
// does not go through SwiftUI at all: each frame samples it from the `AmbientEnergySource`.
//
// Energy rules (ARCHITECTURE.md §9.2): steady frames come from a timer on a render thread of their own
// (`AmbientFrameLoop`), paced at the budget's interval (30 fps on AC, 20 on battery); there is no timer while the
// budget is paused (closed, occluded, full screen), while the window is occluded or gone, or while the view has no
// size. A paused layer keeps its last frame and redraws only when an input changes: at most once per main-queue turn,
// after that turn's layout (a resize frame in the same update already shows the change), and not while the window is
// occluded (it redraws when it is revealed). On resume time continues from the last frame (nothing jumps). The view
// holds its `AmbientRenderer` only while it is in a window (AmbientRenderer.swift explains when the GPU is let go).
//
// Threads: everything here runs on the main thread, which also draws the resize frames, paused redraws, a starting
// loop's first frame and the steady frames that change the layer (AmbientFrameLoop.swift lists them); the render
// thread draws the other steady frames from the inputs this view publishes to the loop (`publish()`) whenever one
// changes. Every change to the layer or the drawable view happens under the loop's lock.
//
// The CAMetalLayer belongs to a subview that covers only the lit band at the bottom of the light, never its clear top
// (AmbientDrawableLayout.swift); this view clips it.
//
// Resizing (the open and close morph, when callers frame the light to the shape's current bounds): every layout
// pass that changes the size draws one frame at the new size and presents it inside the same Core Animation
// transaction, so the light is never shown stretched or a frame behind the shape. Meanwhile the drawable only grows,
// in steps, instead of being reallocated on every frame; the next frame drawn at rest returns it to the band's exact
// size (presented with the transaction too, since its frame changes; the main thread draws it and the frame after it).
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
    /// Live energy the view samples in each frame it draws (nil: `state.energy`).
    var energySource: AmbientEnergySource? = nil

    func makeNSView(context: Context) -> AmbientMetalNSView {
        let view = AmbientMetalNSView()
        view.energySource = energySource
        view.state = state
        return view
    }

    func updateNSView(_ view: AmbientMetalNSView, context: Context) {
        view.energySource = energySource
        view.state = state
    }

    static func dismantleNSView(_ view: AmbientMetalNSView, coordinator: ()) {
        view.stop()
    }
}

final class AmbientMetalNSView: NSView {
    /// The renderer of the GPU this view draws with; held only while the view is in a window.
    private(set) var renderer: AmbientRenderer?
    private let drawableView: AmbientDrawableView
    /// The layer the frames are presented in (tests).
    var metalLayer: CAMetalLayer { drawableView.metalLayer }
    /// The drawable's size and place now; nil until the view first has a size (tests).
    private(set) var drawableLayout: AmbientDrawableLayout?
    /// The drawable's frame or size changed: the next frame is presented with the Core Animation transaction, so the
    /// new frame and the new pixels appear together.
    private var needsSynchronizedFrame = false

    /// Read in every frame drawn, so a running loop follows the energy without any SwiftUI update; a new source
    /// draws nothing by itself (`AmbientEnergySource`). A source with a level is read on the render thread.
    var energySource: AmbientEnergySource? {
        didSet { publish() }
    }

    /// Set by SwiftUI on every update.
    var state: AmbientLayerState? {
        didSet {
            guard state != oldValue else { return }
            if state?.effect != oldValue?.effect { updateDrawableSize() }
            publish()
            stateDidChange()
        }
    }

    /// The steady frames' thread and the frame books (time, last frame, frames drawn) shared with it.
    private let frameLoop: AmbientFrameLoop
    /// The interval the loop runs at; nil while it is paused.
    private var loopInterval: Double?
    /// Frames drawn, and those of them drawn on the render thread (tests and diagnostics).
    var framesDrawn: Int { frameLoop.withShared { $0.framesDrawn } }
    var framesDrawnOffMain: Int { frameLoop.withShared { $0.framesDrawnOffMain } }
    /// Shader time of the last frame drawn (tests).
    var lastFrameTime: Double? { frameLoop.withShared { $0.lastTime } }
    /// Whether the render thread could draw a frame now: it holds the renderer only while it has inputs (tests).
    var renderThreadHasInputs: Bool { frameLoop.withShared { $0.inputs != nil } }
    /// A paused layer's pending redraw of its latest input (one per main-queue turn); tests await it.
    private(set) var pausedRedraw: Task<Void, Never>?
    /// Tests only: their windows are never ordered in, so the window server reports them occluded.
    var treatsWindowAsVisible = false
    /// Whether the frame loop runs now (tests).
    var isRunning: Bool { loopInterval != nil }

    init() {
        let drawableView = AmbientDrawableView()
        self.drawableView = drawableView
        frameLoop = AmbientFrameLoop(layer: drawableView.metalLayer)
        super.init(frame: .zero)
        wantsLayer = true
        layerContentsRedrawPolicy = .never
        clipsToBounds = true                         // a resizing drawable may reach past the bounds (never drawn)
        setAccessibilityElement(false)
        addSubview(drawableView)
        frameLoop.onMainFrame = { [weak self] in self?.drawLoopFrame() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    deinit { frameLoop.stop() }

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
        draw(at: Date(), running: isRunning, synchronized: true)       // in step with the new bounds
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

    /// Takes the renderer of the GPU for this window's display, or lets it go when the view leaves its window (the
    /// render thread's inputs let it go too).
    private func updateRenderer() {
        guard let window else {
            renderer = nil
            frameLoop.withShared { shared in
                metalLayer.device = nil              // the layer would otherwise keep the GPU (and its drawables)
                shared.inputs = inputs
            }
            return
        }
        let display = (window.screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)
            .map { CGDirectDisplayID($0.uint32Value) }
        let next = AmbientRenderer.renderer(forDisplay: display)
        guard next !== renderer else { return }
        renderer = next
        frameLoop.withShared { shared in
            metalLayer.device = next?.device
            shared.inputs = inputs
        }
    }

    /// Pixels per point of the drawable (1 for the soft aurora and halo, the display's scale otherwise).
    private var scale: CGFloat {
        AmbientRenderer.renderScale(for: state?.effect ?? .motes, displayScale: window?.backingScaleFactor ?? 2)
    }

    /// Lays the drawable out for the current bounds, scale and effect: exactly the lit band, or while `resizing` at
    /// least that, grown in steps (AmbientDrawableLayout.swift). A new frame or size is presented with the next frame.
    private func updateDrawableSize(resizing: Bool = false) {
        frameLoop.withShared { shared in
            layOutDrawable(resizing: resizing)
            shared.inputs = inputs
        }
    }

    /// `updateDrawableSize` with the loop's lock held.
    private func layOutDrawable(resizing: Bool = false) {
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

    // MARK: - Inputs of the render thread

    /// What the render thread needs for a steady frame now; nil when this view cannot draw one.
    private var inputs: AmbientFrameLoop.Inputs? {
        guard let state, let renderer, let layout = drawableLayout, hasSize, window != nil else { return nil }
        let level = energySource?.level
        let readsEnergyOffMain = energySource == nil || level != nil
        return AmbientFrameLoop.Inputs(
            state: state, size: bounds.size, scale: scale, layout: layout, renderer: renderer, energy: level,
            drawsOffMain: readsEnergyOffMain && !layout.hasSlack && !needsSynchronizedFrame
                && !metalLayer.presentsWithTransaction)
    }

    /// Hands the render thread the current inputs.
    private func publish() {
        frameLoop.withShared { $0.inputs = inputs }
    }

    // MARK: - Frame loop

    /// Stops the loop for good and lets the renderer go (the view is being dismantled).
    func stop() {
        loopInterval = nil
        frameLoop.stop()                             // the render thread ends
        pausedRedraw?.cancel()
        pausedRedraw = nil
        renderer = nil
        frameLoop.withShared { shared in
            metalLayer.device = nil
            shared.inputs = nil
        }
    }

    private func stateDidChange() {
        updateLoop()                                 // draws the first frame itself when it starts the loop
        // A new effect moved the drawable: show its pixels with its new frame now, not a loop interval later.
        if needsSynchronizedFrame { drawNow(); return }
        // A running loop picks the change up on its next frame; a paused layer redraws (fill and colour animations
        // stay visible while time stands still, e.g. the drain on close).
        if loopInterval == nil { schedulePausedRedraw() }
    }

    /// The paused layer's redraw of its latest input, at the end of this main-queue turn: after the turn's layout, so
    /// an input that changes together with the size (the fill rising during the open morph) costs one frame, the
    /// resize frame, not two. Once per turn however many inputs change; skipped while the window is occluded
    /// (`occlusionDidChange` draws the latest state when it is revealed).
    private func schedulePausedRedraw() {
        frameLoop.withShared { $0.hasUndrawnInput = true }
        guard pausedRedraw == nil else { return }
        pausedRedraw = Task { [weak self] in
            guard let self, !Task.isCancelled else { return }
            self.pausedRedraw = nil
            // Not when a frame (a resize frame) has shown it since, nor while a loop draws or nobody can see it.
            guard self.frameLoop.withShared({ $0.hasUndrawnInput }), self.loopInterval == nil, self.isWindowVisible
            else { return }
            self.drawNow()
        }
    }

    /// The interval the loop should run at now, or nil when it should not run.
    private var wantedInterval: Double? {
        guard let interval = state?.interval, interval > 0, renderer != nil, isWindowVisible, hasSize,
              !isHiddenOrHasHiddenAncestor else { return nil }
        return interval
    }

    /// Starts, retunes or pauses the frame loop to match `wantedInterval`. A loop that starts draws its first frame at
    /// once unless the caller is about to draw one itself (`drawsFirstFrame: false`): one frame per event at most.
    private func updateLoop(drawsFirstFrame: Bool = true) {
        let interval = wantedInterval
        guard interval != loopInterval else { return }
        loopInterval = interval
        frameLoop.run(at: interval)
        if interval != nil, drawsFirstFrame { draw(at: Date(), running: true) }     // the first frame without waiting
    }

    private func drawNow() { draw(at: Date(), running: isRunning) }

    /// A steady frame the render thread left to the main thread (`AmbientFrameLoop.Inputs.drawsOffMain`); skipped
    /// when the loop has paused since, or a resize frame was drawn less than half an interval ago.
    private func drawLoopFrame() {
        let skips = frameLoop.withShared { shared -> Bool in
            shared.mainFrameRequested = false
            guard let interval = shared.interval else { return true }
            guard let last = shared.lastDrawn else { return false }
            return ContinuousClock.now - last < .seconds(interval / 2)
        }
        guard !skips else { return }
        draw(at: Date(), running: true)
    }

    /// Draws one frame. `synchronized`: a resize frame, presented with the new bounds (its drawable may be larger than
    /// the band). Any other frame first returns the drawable to the band's exact size.
    private func draw(at date: Date, running: Bool, synchronized: Bool = false) {
        guard state != nil, renderer != nil, hasSize, window != nil else { return }
        let energy = energySource?.sample()
        frameLoop.withShared { shared in
            if !synchronized { layOutDrawable() }
            guard let frame = inputs else { return }
            if AmbientFrameLoop.draw(&shared, frame, energy: energy, layer: metalLayer, at: date, running: running,
                                     synchronized: synchronized || needsSynchronizedFrame) {
                needsSynchronizedFrame = false
            }
            shared.inputs = inputs                     // after this frame (its layout, the layer's present mode)
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
