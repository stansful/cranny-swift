// CrannyEffects/CoreAnimation/AmbientCALayer.swift — the ambient light of Appearance ▸ Quality ▸ Efficient
// (DESIGN.md §5.7): Core Animation layers that the window server renders and animates.
//
// Why: any Metal work in the process (the dedicated Metal layer, a SwiftUI shader, a Canvas or MeshGradient fallback)
// makes the GPU driver charge its working set to Cranny (≈ 240 MB on an M4 Max) while the light runs, and every frame
// wakes the app. Here the app builds layers and looping animations once; the window server's render server moves them,
// so the light costs Cranny no GPU memory and no wake-up per frame (ARCHITECTURE.md §9.2 measures what moves to the
// window server).
//
// Layer tree (y down, like SwiftUI and the shaders):
//   view layer (clips) → fill layer: the rise from the bottom edge (a mask while 0 < fill < 1, an opacity fade under
//   Reduce Motion) and the target of the cross-fades (a `CATransition` for palette, level and effect changes)
//     → the effect's group: alpha cap (group opacity) and its static mask (AmbientCAEffects.swift)
//       → swell layer: the song-change lift, in real time (the tide deepens its waves under the clock instead)
//         → clock layer: every looping animation lives under it (AmbientCAState.swift explains the clock)
//           → the effect's content.
//
// Energy (ARCHITECTURE.md §9.2): the budget pauses the light (closed, occluded, full screen) by stopping the clock
// layer (speed 0); Reduce Motion and Motion ▸ Instant stop it on the resting frame; a resumed clock continues where it
// stopped. Animations ask for the budget's frame rate (`preferredFrameRateRange`: 30 fps on AC, 20 on battery) and are
// installed again only when that rate changes; how often the window server composites is its own choice (on a 240-Hz
// display it was measured at the display's rate, ARCHITECTURE.md §9.2). Nothing here runs a timer, and a resize moves
// layers without touching an animation.
import AppKit
import CrannyCore
import Foundation
import QuartzCore
import SwiftUI

/// SwiftUI host of `AmbientCANSView`. Used by `AmbientFieldView` on the `.coreAnimation` path.
struct AmbientCALayer: NSViewRepresentable {
    var state: AmbientCAState

    func makeNSView(context: Context) -> AmbientCANSView {
        let view = AmbientCANSView()
        view.state = state
        return view
    }

    func updateNSView(_ view: AmbientCANSView, context: Context) {
        view.state = state
    }

    static func dismantleNSView(_ view: AmbientCANSView, coordinator: ()) {
        view.stop()
    }
}

final class AmbientCANSView: NSView {
    private let fillLayer = AmbientCA.still(CALayer())
    /// `FillMask`'s gradient (clear above the rising edge, opaque below, a 25 % soft edge), only while it shows anything.
    private let fillMask = AmbientCA.still(CAGradientLayer())
    private let swellLayer = AmbientCA.still(CALayer())
    private let clockLayer = AmbientCA.still(CALayer())
    /// The effect drawn now; nil until the first state (or after `stop()`).
    private(set) var effect: (any AmbientCAEffect)?
    /// The effect and halo placement `effect` was built for.
    private var builtFor: (effect: AmbientEffect, halo: HaloPlacement)?
    /// The frame rate the looping animations were installed at.
    private(set) var installedFrameRate: Float?
    /// The light's time while the clock stands still (the frame shown), in seconds.
    private var stoppedTime: Double = 0
    private(set) var isClockRunning = false
    /// The last song change that lifted the light (each date lifts it once).
    private var swelledFor: Date?

    /// Set by SwiftUI on every update; only what changed is applied.
    var state: AmbientCAState? {
        didSet {
            guard state != oldValue else { return }
            apply(previous: oldValue)
        }
    }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layerContentsRedrawPolicy = .never
        clipsToBounds = true
        setAccessibilityElement(false)
        layer?.addSublayer(fillLayer)
        swellLayer.addSublayer(clockLayer)
        fillMask.startPoint = CGPoint(x: 0.5, y: 0)
        fillMask.endPoint = CGPoint(x: 0.5, y: 1)
        fillMask.colors = (0...4).map { CGColor(gray: 1, alpha: CGFloat(Easing.easeInOut(Double($0) / 4))) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    /// Top-left origin, so the layers' geometry is the shaders' and SwiftUI's (y down).
    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }
    /// Light never takes a click (the panel's per-pixel pass-through relies on it).
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    // MARK: - Size and scale

    override func setFrameSize(_ newSize: NSSize) {
        let changed = newSize != frame.size
        super.setFrameSize(newSize)
        if changed { layOut() }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        layOut()
        updateScale()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateScale()
    }

    /// Every layer for the current bounds. Geometry only: the animations are fractions of it, so none is touched.
    private func layOut() {
        withoutActions {
            let rect = CGRect(origin: .zero, size: bounds.size)
            for layer in [fillLayer, fillMask, swellLayer, clockLayer] { layer.frame = rect }
            if let effect {
                effect.group.frame = rect
                effect.content.frame = rect
                effect.layout(bounds.size)
            }
        }
    }

    /// Strokes and gradients render at the display's pixel density.
    private func updateScale() {
        let scale = window?.backingScaleFactor ?? 2
        withoutActions {
            func visit(_ layer: CALayer) {
                if layer.contentsScale != scale { layer.contentsScale = scale }
                layer.sublayers?.forEach(visit)
                if let mask = layer.mask { visit(mask) }
            }
            visit(fillLayer)
            visit(fillMask)
        }
    }

    // MARK: - State

    /// Stops the light for good: the effect's layers go (the view is being dismantled).
    func stop() {
        withoutActions {
            effect?.group.removeFromSuperlayer()
            clockLayer.sublayers?.forEach { $0.removeFromSuperlayer() }
            fillLayer.removeAllAnimations()
            swellLayer.removeAllAnimations()
        }
        effect = nil
        builtFor = nil
        installedFrameRate = nil
        isClockRunning = false
    }

    private func apply(previous: AmbientCAState?) {
        guard let state else { return }
        withoutActions {
            let wanted = (effect: state.effect, halo: state.halo)
            let rebuilds = effect == nil || builtFor?.effect != wanted.effect
                || (wanted.effect == .halo && builtFor?.halo != wanted.halo)
            let restyles = previous?.glows != state.glows || previous?.level != state.level
            // Palette, level and effect changes cross-fade on the fill layer (outside the clock, so a stopped light
            // fades too); a fade already playing takes the newer look on its incoming side.
            if previous != nil, rebuilds || restyles, let fade = state.crossFade {
                crossFade(fade, interval: state.interval)
            }
            if rebuilds {
                build(state)
            } else if restyles {
                effect?.apply(glows: state.glows, level: state.level)
            }
            effect?.group.opacity = Float(Glow.ambientAlphaCap(state.level))
            applyFill(state)
            applyClock(state)
            applySwell(state)
        }
    }

    /// Builds the effect's layers for `state` and puts them in the tree, its content under the clock.
    private func build(_ state: AmbientCAState) {
        effect?.group.removeFromSuperlayer()
        let next: any AmbientCAEffect = switch state.effect {
        case .aurora: AuroraCA()
        case .motes: MotesCA()
        case .tide: TideCA()
        case .halo: HaloCA(placement: state.halo)
        }
        clockLayer.sublayers?.forEach { $0.removeFromSuperlayer() }
        clockLayer.addSublayer(next.content)
        next.group.addSublayer(swellLayer)
        fillLayer.addSublayer(next.group)
        if effect == nil {                       // the first light opens on its resting frame, stopped until the budget
            stoppedTime = state.restingTime      // runs it (a new clock layer would follow the media clock at speed 1)
            setClock(running: false)
        }
        effect = next
        builtFor = (state.effect, state.halo)
        installedFrameRate = nil
        next.apply(glows: state.glows, level: state.level)
        layOut()
        updateScale()
    }

    /// `FillMask` on the fill layer while the light rises or drains; an opacity fade while it rests (Reduce Motion).
    private func applyFill(_ state: AmbientCAState) {
        let fill = min(max(state.fill, 0), 1)
        if state.rests || fill >= 1 || fill <= 0 {
            if fillLayer.mask != nil { fillLayer.mask = nil }
            fillLayer.opacity = Float(state.rests ? fill : (fill <= 0 ? 0 : 1))
            return
        }
        let soft = 0.25
        let edge = 1 - fill * (1 + soft)
        fillMask.startPoint = CGPoint(x: 0.5, y: edge)
        fillMask.endPoint = CGPoint(x: 0.5, y: edge + soft)
        fillLayer.opacity = 1
        if fillLayer.mask !== fillMask { fillLayer.mask = fillMask }
    }

    /// Runs, stops or rests the clock, and installs the animations at the budget's rate (AmbientCAState.swift).
    private func applyClock(_ state: AmbientCAState) {
        let running = state.interval != nil && !state.rests
        if let interval = state.interval {
            let rate = AmbientCAClock.frameRate(interval: interval)
            if rate != installedFrameRate { install(rate: rate) }
        } else if installedFrameRate == nil {
            install(rate: AmbientCAClock.frameRate(interval: nil))
        }
        if state.rests {
            effect?.stopSwell()                     // the clock jumps: a tide swell must not wait for its time
            stoppedTime = state.restingTime
            setClock(running: false)
        } else if running != isClockRunning {
            if !running { stoppedTime = lightTime }
            setClock(running: running)
        }
    }

    private func install(rate: Float) {
        effect?.installAnimations(frameRate: rate)
        installedFrameRate = rate
    }

    private func setClock(running: Bool) {
        let timing = AmbientCAClock.timing(time: stoppedTime, running: running, parentNow: parentNow)
        clockLayer.speed = timing.speed
        clockLayer.beginTime = timing.beginTime
        clockLayer.timeOffset = timing.timeOffset
        isClockRunning = running
    }

    /// The clock layer's parent time now.
    private var parentNow: CFTimeInterval { swellLayer.convertTime(CACurrentMediaTime(), from: nil) }

    /// The light's time shown now, in seconds (the clock's local time less the epoch).
    var lightTime: Double {
        AmbientCAClock.time(of: AmbientCAClock.Timing(speed: clockLayer.speed, beginTime: clockLayer.beginTime,
                                                      timeOffset: clockLayer.timeOffset), parentNow: parentNow)
    }

    /// The light's own tree (the fill layer and everything under it), for rendering it offscreen (tests).
    var lightLayer: CALayer { fillLayer }

    /// The clock layer's speed: 1 while the light moves, 0 while it stands still (tests).
    var clockSpeed: Float { clockLayer.speed }

    /// The clock layer itself: the effect's content lives under it (tests).
    var clockLayerForTests: CALayer { clockLayer }

    /// The layer that lifts the whole light for a song change (tests).
    var swellLayerForTests: CALayer { swellLayer }

    /// Whether the fill mask shows now (tests).
    var isFillMasked: Bool { fillLayer.mask != nil }

    /// The fill layer's opacity (tests).
    var fillOpacity: Float { fillLayer.opacity }

    /// A new song change lifts the light by 3 % of its height (at most 8 pt) and lets it settle within the ripple's
    /// 0.6 s: the shaders' energy pulse, without the distortion (the tide deepens its waves in place instead,
    /// `TideCA.playSwell`). Only while the light moves, once per change; a change that arrived while the light was
    /// paused plays only the part of the swell that is left.
    private func applySwell(_ state: AmbientCAState) {
        guard let start = state.rippleStart, start != swelledFor, isClockRunning,
              let elapsed = Ripple.elapsed(since: start, at: Date()) else { return }
        swelledFor = start
        let rate = installedFrameRate ?? 30
        if effect?.playSwell(elapsed: elapsed, frameRate: rate) == true { return }
        let lift = min(max(0.03 * bounds.height, 3), 8)
        swellLayer.add(AmbientCA.swell("transform.translation.y", values: [0, -lift, -lift * 0.35, 0],
                                       elapsed: elapsed, on: swellLayer, frameRate: rate),
                       forKey: AmbientCA.swellKey)
    }

    /// One cross-fade of the whole light (old look → new look) on the fill layer, unless one is playing. Core Animation
    /// keeps a layer's transition under `kCATransition`.
    private func crossFade(_ fade: AmbientCAFade, interval: Double?) {
        guard fillLayer.animation(forKey: kCATransition) == nil else { return }
        let transition = CATransition()
        transition.type = .fade
        transition.duration = fade.duration
        transition.timingFunction = fade.timingFunction
        transition.preferredFrameRateRange = frameRange(AmbientCAClock.frameRate(interval: interval))
        fillLayer.add(transition, forKey: kCATransition)
    }

    private func frameRange(_ rate: Float) -> CAFrameRateRange {
        CAFrameRateRange(minimum: max(rate / 2, 1), maximum: rate, preferred: rate)
    }

    private func withoutActions(_ body: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        body()
        CATransaction.commit()
    }
}

// MARK: - Previews

#Preview("Core Animation light · aurora, motes, tide") {
    VStack(spacing: Space.s) {
        ForEach([AmbientEffect.aurora, .motes, .tide], id: \.self) { effect in
            AmbientCALayer(state: AmbientCAState(effect: effect, glows: AmbientPalette.afterglow.glows, level: .vivid,
                                                 fill: 1, interval: 1.0 / 30, rests: false, restingTime: 7.3,
                                                 halo: .ambient, rippleStart: nil,
                                                 crossFade: AmbientCAFade(duration: 0.8, curve: .easeInEaseOut)))
            .frame(width: 656, height: 170)
        }
    }
    .padding(Space.m)
    .background(.black)
    .crannyThemeRoot(CrannyTheme())
}
