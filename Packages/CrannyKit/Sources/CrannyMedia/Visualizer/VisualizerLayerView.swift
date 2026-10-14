// CrannyMedia/Visualizer/VisualizerLayerView.swift — the 5-bar renderer on Core Animation layers (ARCHITECTURE.md
// §6.6): never SwiftUI TimelineView + Canvas for always-on bars (4.6–4.8 % CPU vs 0.06–0.34 %, R2 §8).
//   • Ambient: one precomputed loop per bar as a CAKeyframeAnimation, run by the render server at ≤ 30 fps
//     (≤ 20 on battery) through `preferredFrameRateRange`: zero work in the app while it plays.
//   • Live: heights pushed by `VisualizerEngine` (`LevelSink`) inside `CATransaction.setDisableActions`.
//   • Dots: paused / Static / Reduce Motion; the bars ease to 3-pt dots over 400 ms (instantly under Reduce Motion).
// Off screen (no window, occluded) every animation is removed: nothing runs while hidden.
import AppKit
import CrannyCore
import QuartzCore
import SwiftUI

/// Bar geometry in points (already multiplied by the notch unit where it applies).
nonisolated struct VisualizerMetrics: Equatable, Sendable {
    var barWidth: CGFloat = 3
    var gap: CGFloat = 2
    var minHeight: CGFloat = 4
    var maxHeight: CGFloat = 16

    var width: CGFloat { CGFloat(SyntheticSpectrum.barCount) * barWidth + CGFloat(SyntheticSpectrum.barCount - 1) * gap }
    /// A dot is a bar as tall as it is wide.
    var dot: CGFloat { barWidth }

    func height(for level: Double) -> CGFloat { max(minHeight, min(CGFloat(level), 1) * maxHeight) }

    /// Compact band (DESIGN.md §9.2): 3-pt bars, 2-pt gaps, 4–16 pt, × notch unit.
    static func compact(unit: CGFloat) -> VisualizerMetrics {
        VisualizerMetrics(barWidth: 3 * unit, gap: 2 * unit, minHeight: 4 * unit, maxHeight: 16 * unit)
    }
    /// Beside the artist line in the Media widget.
    static let widget = VisualizerMetrics(barWidth: 2.5, gap: 2, minHeight: 3, maxHeight: 12)
}

struct VisualizerConfiguration: Equatable {
    var render: VisualizerRender
    var metrics: VisualizerMetrics
    var color: RGB
    var fps: Double
    var reduceMotion: Bool
}

/// SwiftUI wrapper. Decorative: hidden from accessibility, never takes clicks.
struct VisualizerLayerView: NSViewRepresentable {
    let configuration: VisualizerConfiguration
    let engine: VisualizerEngine

    func makeNSView(context: Context) -> VisualizerNSView {
        let view = VisualizerNSView(engine: engine)
        view.apply(configuration)
        return view
    }

    func updateNSView(_ view: VisualizerNSView, context: Context) { view.apply(configuration) }

    static func dismantleNSView(_ view: VisualizerNSView, coordinator: ()) { view.teardown() }
}

final class VisualizerNSView: NSView, LevelSink {
    private let engine: VisualizerEngine
    private var bars: [CALayer] = []
    private var configuration: VisualizerConfiguration?
    private var installed: VisualizerRender?           // what the layers currently animate
    private var installedFPS: Double = 0
    private var occlusionObserver: (any NSObjectProtocol)?
    private var isAttached = false

    init(engine: VisualizerEngine) {
        self.engine = engine
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = false
        for _ in 0..<SyntheticSpectrum.barCount {
            let bar = CALayer()
            bar.actions = ["bounds": NSNull(), "position": NSNull(), "backgroundColor": NSNull()]
            layer?.addSublayer(bar)
            bars.append(bar)
        }
    }

    @available(*, unavailable) required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }        // decorative: clicks go to the notch

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let observer = occlusionObserver { NotificationCenter.default.removeObserver(observer) }
        occlusionObserver = nil
        if let window {
            occlusionObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }                // queue: .main
            }
        }
        refresh()
    }

    override func layout() {
        super.layout()
        refresh()                      // re-centres the bars; running animations keep going
    }

    func apply(_ configuration: VisualizerConfiguration) {
        let colorChanged = self.configuration?.color != configuration.color
        self.configuration = configuration
        if colorChanged { recolor(animated: installed != nil && !configuration.reduceMotion) }
        refresh()
    }

    func teardown() {
        if let observer = occlusionObserver { NotificationCenter.default.removeObserver(observer) }
        occlusionObserver = nil
        if isAttached { engine.detach(self); isAttached = false }
        for bar in bars { bar.removeAllAnimations() }
    }

    // MARK: LevelSink

    func receive(levels: [Double]) {
        guard let configuration, installed == .live, case .live = configuration.render else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (bar, level) in zip(bars, levels) { setHeight(configuration.metrics.height(for: level), of: bar) }
        CATransaction.commit()
    }

    // MARK: Rendering

    private var isOnScreen: Bool {
        guard let window else { return false }
        return window.occlusionState.contains(.visible)
    }

    private func refresh() {
        guard let configuration else { return }
        let visible = isOnScreen
        if visible != isAttached {
            isAttached = visible
            if visible { engine.attach(self) } else { engine.detach(self) }
        }
        layoutBars(configuration.metrics)
        guard visible else {
            if installed != nil { rest(animated: false) }
            return
        }
        let target = configuration.render
        guard target != installed || configuration.fps != installedFPS else { return }
        switch target {
        case .hidden, .dots:
            rest(animated: installed != nil && !configuration.reduceMotion)
        case .ambient(let spectrum):
            installLoops(spectrum, configuration)
        case .live:
            for bar in bars { bar.removeAllAnimations() }
            installed = .live
        }
        installedFPS = configuration.fps
    }

    private func layoutBars(_ metrics: VisualizerMetrics) {
        let midY = bounds.midY
        let originX = (bounds.width - metrics.width) / 2
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (i, bar) in bars.enumerated() {
            bar.cornerRadius = metrics.barWidth / 2
            bar.position = CGPoint(x: originX + CGFloat(i) * (metrics.barWidth + metrics.gap) + metrics.barWidth / 2, y: midY)
            if bar.bounds.width != metrics.barWidth || bar.bounds.height == 0 {
                bar.bounds = CGRect(x: 0, y: 0, width: metrics.barWidth, height: metrics.dot)
            }
        }
        CATransaction.commit()
        if bars.first?.backgroundColor == nil { recolor(animated: false) }
    }

    private func recolor(animated: Bool) {
        guard let color = configuration?.color.nsColor.cgColor else { return }
        for bar in bars {
            if animated {
                let fade = CABasicAnimation(keyPath: "backgroundColor")
                fade.fromValue = bar.presentation()?.backgroundColor ?? bar.backgroundColor
                fade.toValue = color
                fade.duration = 0.8                                   // `colorShift` (DESIGN.md §4.1)
                fade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                bar.add(fade, forKey: "color")
            }
            bar.backgroundColor = color
        }
    }

    /// Eases every bar to a dot (paused / Static / Reduce Motion / off screen).
    private func rest(animated: Bool) {
        guard let metrics = configuration?.metrics else { return }
        for bar in bars {
            let current = bar.presentation()?.bounds.height ?? bar.bounds.height
            bar.removeAnimation(forKey: "ramp")
            bar.removeAnimation(forKey: "loop")
            setHeight(metrics.dot, of: bar)
            guard animated, abs(current - metrics.dot) > 0.5 else { continue }
            let ease = CABasicAnimation(keyPath: "bounds.size.height")
            ease.fromValue = current
            ease.toValue = metrics.dot
            ease.duration = SyntheticSpectrum.restDuration
            ease.timingFunction = CAMediaTimingFunction(name: .easeOut)
            bar.add(ease, forKey: "rest")
        }
        installed = .dots
    }

    /// Ramps from the current height into one loop of the spectrum, repeated forever by the render server.
    private func installLoops(_ spectrum: SyntheticSpectrum, _ configuration: VisualizerConfiguration) {
        let metrics = configuration.metrics
        let now = CACurrentMediaTime()
        let ramp = 0.3
        let range = CAFrameRateRange(minimum: 10, maximum: Float(configuration.fps), preferred: Float(configuration.fps))
        for (i, bar) in bars.enumerated() {
            let current = bar.presentation()?.bounds.height ?? bar.bounds.height
            bar.removeAllAnimations()
            let values = spectrum.keyframes(bar: i, fps: configuration.fps).map { metrics.height(for: $0) }
            setHeight(metrics.dot, of: bar)                                // model value = rest

            let rise = CABasicAnimation(keyPath: "bounds.size.height")
            rise.fromValue = current
            rise.toValue = values.first ?? metrics.minHeight
            rise.duration = ramp
            rise.timingFunction = CAMediaTimingFunction(name: .easeOut)
            rise.fillMode = .forwards
            rise.isRemovedOnCompletion = false
            rise.preferredFrameRateRange = range
            bar.add(rise, forKey: "ramp")

            let loop = CAKeyframeAnimation(keyPath: "bounds.size.height")
            loop.values = values + [values.first ?? metrics.minHeight]       // close the cycle
            loop.calculationMode = .linear
            loop.duration = spectrum.loopDuration
            loop.beginTime = now + ramp
            loop.repeatCount = .infinity
            loop.preferredFrameRateRange = range
            bar.add(loop, forKey: "loop")
        }
        installed = .ambient(spectrum)
    }

    private func setHeight(_ height: CGFloat, of bar: CALayer) {
        var bounds = bar.bounds
        bounds.size.height = height
        bar.bounds = bounds
    }
}
