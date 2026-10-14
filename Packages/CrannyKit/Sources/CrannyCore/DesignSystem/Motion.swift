// CrannyCore/DesignSystem/Motion.swift
// Every animation in Cranny comes from this table. Rule: geometry may overshoot when it
// GROWS; it never overshoots when it SHRINKS back into the hardware.
import SwiftUI

/// Settings ▸ Appearance ▸ Motion. Scales bounce only; durations are fixed.
public nonisolated enum MotionPersonality: String, CaseIterable, Codable, Sendable {
    case calm       // no bounce anywhere
    case standard   // default
    case lively     // bounce × 1.5 (capped at 0.35)
    case instant    // no animation at all
    public var bounceScale: Double {
        switch self {
        case .calm, .instant: 0
        case .standard: 1
        case .lively: 1.5
        }
    }
}

public nonisolated enum CrannyMotion {
    public nonisolated enum Kind: String, CaseIterable, Sendable {
        // Shape geometry
        case open, close, resize, activityIn, activityOut, activitySwap
        case peekIn, peekOut, hoverIn, hoverOut, satellite, hudIn, hudLevel, hudOut
        // Content
        case contentIn, contentOut, contentSwap, tab, tabIndicator, colorShift, ambientIn, ambientOut
        // Controls & direct manipulation
        case hover, press, commit, listReorder, snapBack
    }

    public nonisolated enum Curve: Equatable, Sendable {
        case spring(duration: Double, bounce: Double)
        case easeOut(Double), easeIn(Double), easeInOut(Double), smooth(Double)
    }

    public nonisolated struct Spec: Equatable, Sendable {
        public let curve: Curve
        public let delay: Double
        /// Shrinking toward the hardware: bounce is forced to 0 for every personality.
        public let lands: Bool
        init(_ curve: Curve, delay: Double = 0, lands: Bool = false) { self.curve = curve; self.delay = delay; self.lands = lands }
    }

    /// The Standard table (DESIGN.md §4.1).
    public static func spec(_ k: Kind) -> Spec {
        switch k {
        case .open:          Spec(.spring(duration: 0.42, bounce: 0.14))
        case .close:         Spec(.spring(duration: 0.34, bounce: 0), lands: true)
        case .resize:        Spec(.spring(duration: 0.40, bounce: 0.10))
        case .activityIn:    Spec(.spring(duration: 0.46, bounce: 0.24))
        case .activityOut:   Spec(.spring(duration: 0.30, bounce: 0), lands: true)
        case .activitySwap:  Spec(.spring(duration: 0.30, bounce: 0.04))
        case .peekIn:        Spec(.spring(duration: 0.38, bounce: 0.14))
        case .peekOut:       Spec(.spring(duration: 0.28, bounce: 0), lands: true)
        case .hoverIn:       Spec(.spring(duration: 0.26, bounce: 0.20))
        case .hoverOut:      Spec(.spring(duration: 0.24, bounce: 0), lands: true)
        case .satellite:     Spec(.spring(duration: 0.38, bounce: 0.18))
        case .hudIn:         Spec(.spring(duration: 0.30, bounce: 0.16))
        case .hudLevel:      Spec(.spring(duration: 0.16, bounce: 0))
        case .hudOut:        Spec(.spring(duration: 0.30, bounce: 0), lands: true)
        case .contentIn:     Spec(.easeOut(0.22), delay: 0.06)
        case .contentOut:    Spec(.easeIn(0.10))
        case .contentSwap:   Spec(.smooth(0.30))
        case .tab:           Spec(.spring(duration: 0.26, bounce: 0))
        case .tabIndicator:  Spec(.spring(duration: 0.30, bounce: 0.10))
        case .colorShift:    Spec(.easeInOut(0.80))
        case .ambientIn:     Spec(.easeOut(0.50), delay: 0.10)
        case .ambientOut:    Spec(.easeIn(0.20))
        case .hover:         Spec(.easeOut(0.12))
        case .press:         Spec(.spring(duration: 0.18, bounce: 0.20))
        case .commit:        Spec(.spring(duration: 0.30, bounce: 0))
        case .listReorder:   Spec(.spring(duration: 0.32, bounce: 0.06))
        case .snapBack:      Spec(.spring(duration: 0.36, bounce: 0.12))
        }
    }

    /// Reduce Motion: big morphs become dissolves at the final size (see `morphsShape`),
    /// small morphs lose their bounce, nothing scales/blurs/slides.
    public static func reducedSpec(_ k: Kind) -> Curve? {
        switch k {
        case .open, .close, .resize: .easeInOut(0.20)
        case .activityIn, .activityOut, .activitySwap, .peekIn, .peekOut, .satellite, .hudIn, .hudOut: .easeInOut(0.18)
        case .hoverIn, .hoverOut, .hudLevel: nil
        case .contentIn: .easeOut(0.15)
        case .contentOut: .easeIn(0.08)
        case .contentSwap, .tab, .tabIndicator: .easeInOut(0.15)
        case .colorShift: .easeInOut(0.30)
        case .ambientIn, .ambientOut: .easeInOut(0.20)
        case .hover, .press: .easeOut(0.08)
        case .commit, .listReorder, .snapBack: .easeOut(0.18)
        }
    }

    public static func animation(_ k: Kind, personality: MotionPersonality = .standard,
                                 reduceMotion: Bool = false) -> Animation? {
        if personality == .instant { return nil }
        if reduceMotion { return reducedSpec(k).map { make($0) } }
        let s = spec(k)
        var curve = s.curve
        if case .spring(let d, let b) = curve {
            let bounce = s.lands ? 0 : min(b * personality.bounceScale, 0.35)
            curve = .spring(duration: d, bounce: bounce)
        }
        let a = make(curve)
        return s.delay > 0 ? a.delay(s.delay) : a
    }

    private static func make(_ c: Curve) -> Animation {
        switch c {
        case .spring(let d, let b): .spring(duration: d, bounce: b)
        case .easeOut(let d): .easeOut(duration: d)
        case .easeIn(let d): .easeIn(duration: d)
        case .easeInOut(let d): .easeInOut(duration: d)
        case .smooth(let d): .smooth(duration: d)
        }
    }

    /// With Reduce Motion, open/close/resize do not travel: the old and new shapes cross-fade
    /// at their final sizes. Small morphs (compact, peek, HUD) still morph, without bounce.
    public static func morphsShape(_ k: Kind, reduceMotion: Bool) -> Bool {
        !(reduceMotion && (k == .open || k == .close || k == .resize))
    }

    /// Widgets enter radiating outward from the camera: `ring` = |column distance from the
    /// centre| in widget order. 18 ms per ring, at most 4 rings (72 ms).
    public static func stagger(ring: Int, reduceMotion: Bool) -> Double {
        reduceMotion ? 0 : Double(min(max(ring, 0), 4)) * 0.018
    }

    /// iOS-style rubber band: resistance grows with distance and never hard-stops.
    public static func rubberBand(_ offset: CGFloat, limit: CGFloat, coefficient c: CGFloat = 0.55) -> CGFloat {
        guard limit > 0 else { return 0 }
        let sign: CGFloat = offset < 0 ? -1 : 1
        return sign * (1 - 1 / (abs(offset) * c / limit + 1)) * limit
    }

    /// Hand the gesture's velocity (pt/s) to the spring so a release never "restarts".
    public static func release(velocity: CGFloat, remaining distance: CGFloat) -> Animation {
        let v = abs(distance) < 0.5 ? 0 : Double(velocity / distance)
        return .interpolatingSpring(duration: 0.40, bounce: 0.14, initialVelocity: v)
    }
}

// MARK: - Hover intent (the anti-flicker contract)

public nonisolated enum HoverIntent {
    /// Settings ▸ General ▸ Hover delay.
    public nonisolated enum Delay: String, CaseIterable, Codable, Sendable {
        case instant, short, standard, long
        public var seconds: Double { switch self { case .instant: 0; case .short: 0.12; case .standard: 0.22; case .long: 0.45 } }
    }
    public static let defaultDelay = Delay.short
    public static let peekDwell: Double = 0.18           // compact → peek
    public static let fullScreenDwell: Double = 0.40     // in a full-screen Space (tabs/toolbars live up there)
    public static let closeGrace: Double = 0.30          // leave the exit zone this long before closing
    public static let entryInflation: CGFloat = 4        // + the very top pixel row (mouse y == frame.maxY)
    public static let exitInflation: CGFloat = 14        // hysteresis while open
    public static let passThroughSpeed: CGFloat = 1200   // pt/s: travelling to a menu or display, not aiming
    public static let dragProximity = CGSize(width: 80, height: 40)   // file drag opens the Tray, no dwell
    public static let menuBarCourtesy: CGFloat = 24      // pointer this close beside the wings → wings retract
    public static let peekAutoDismiss: Double = 2.6
    public static let hudAutoDismiss: Double = 1.5

    /// Pure decision function (unit-tested). The shell calls it from its pointer monitor.
    public static func shouldOpen(dwell: Double, pointerSpeed: CGFloat, delay: Delay,
                                  mouseButtonDown: Bool, optionHeld: Bool,
                                  isFileDrag: Bool, fullScreenSpace: Bool) -> Bool {
        if isFileDrag { return true }
        if mouseButtonDown || optionHeld { return false }
        if pointerSpeed > passThroughSpeed { return false }
        return dwell >= (fullScreenSpace ? max(delay.seconds, fullScreenDwell) : delay.seconds)
    }
}

/// Two-finger trackpad gestures over the shape (precise scroll deltas only, R1 §6).
public nonisolated enum GestureSpec {
    public static let trackSwipeCommit: CGFloat = 40       // pt of finger travel …
    public static let trackSwipeVelocity: CGFloat = 400    // … or pt/s at release
    public static let pullOpen: CGFloat = 24               // swipe down on closed/compact
    public static let pushClose: CGFloat = 18              // swipe up on open/compact/peek
    public static let verticalVelocity: CGFloat = 300
    public static let horizontalTravel: CGFloat = 24       // rubber-band limit for content
    public static let verticalTravel: CGFloat = 20         // rubber-band limit for the shape
    public static let axisLock: CGFloat = 1.6              // dominant axis ≥ 1.6 × the other
    public static let cooldown: Double = 0.15              // one gesture per touch sequence
    public static let limitBump: CGFloat = 2               // HUD bar overshoot when pressing past 0 / 100 %
}

// MARK: - Transitions

/// Blur + scale + fade. Content materialises out of the notch and leaves before the shape shrinks.
public nonisolated struct BlurScale: ViewModifier {
    public var blur: CGFloat, scale: CGFloat, opacity: Double, anchor: UnitPoint
    public func body(content: Content) -> some View {
        content.blur(radius: blur).scaleEffect(scale, anchor: anchor).opacity(opacity)
    }
}

public extension AnyTransition {
    /// Nook/peek content. Reduce Motion → opacity only.
    static func crannyContent(reduceMotion: Bool, anchor: UnitPoint = .top) -> AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .modifier(active: BlurScale(blur: 6, scale: 0.96, opacity: 0, anchor: anchor),
                                 identity: BlurScale(blur: 0, scale: 1, opacity: 1, anchor: anchor)),
            removal: .modifier(active: BlurScale(blur: 3, scale: 0.98, opacity: 0, anchor: anchor),
                               identity: BlurScale(blur: 0, scale: 1, opacity: 1, anchor: anchor)))
    }
    /// Compact slot content grows out of the camera edge (anchored on the camera side).
    static func crannySlot(edge: HorizontalEdge, reduceMotion: Bool) -> AnyTransition {
        guard !reduceMotion else { return .opacity }
        let anchor: UnitPoint = edge == .leading ? .trailing : .leading
        return .modifier(active: BlurScale(blur: 4, scale: 0.6, opacity: 0, anchor: anchor),
                         identity: BlurScale(blur: 0, scale: 1, opacity: 1, anchor: anchor))
    }
    /// Tab/page switch: symmetric, direction-aware ±12 pt slide + fade (never "fades one way, slides the other").
    static func crannyTab(forward: Bool, reduceMotion: Bool) -> AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(insertion: .offset(x: forward ? 12 : -12).combined(with: .opacity),
                           removal: .offset(x: forward ? -12 : 12).combined(with: .opacity))
    }
}
