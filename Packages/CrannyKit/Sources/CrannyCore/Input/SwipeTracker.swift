// CrannyCore/Input/SwipeTracker.swift
// Pure two-finger swipe state machine (extends R1 §6's verified recognizer with live tracking for
// rubber-banding, DESIGN.md §4.4). No AppKit state: unit-test it with synthetic samples.
import CoreGraphics
import Foundation

/// The axis a gesture locks to.
public nonisolated enum SwipeAxis: Sendable, Equatable { case horizontal, vertical, any }
/// The direction of a committed swipe, in physical finger motion.
public nonisolated enum SwipeDirection: Sendable, Equatable { case left, right, up, down }

/// Scroll phases (mirrors NSEvent.Phase without importing AppKit).
public nonisolated struct SwipePhase: OptionSet, Sendable, Hashable {
    /// The phase bits.
    public let rawValue: Int
    /// Phases from raw bits.
    public init(rawValue: Int) { self.rawValue = rawValue }
    /// Fingers touched down.
    public static let began = SwipePhase(rawValue: 1 << 0)
    /// Fingers rest without moving.
    public static let stationary = SwipePhase(rawValue: 1 << 1)
    /// Fingers moved.
    public static let changed = SwipePhase(rawValue: 1 << 2)
    /// Fingers lifted.
    public static let ended = SwipePhase(rawValue: 1 << 3)
    /// The system cancelled the sequence.
    public static let cancelled = SwipePhase(rawValue: 1 << 4)
    /// Fingers touched down before any movement.
    public static let mayBegin = SwipePhase(rawValue: 1 << 5)
}

/// One scroll event, reduced to what the tracker needs (no AppKit).
public nonisolated struct ScrollSample: Sendable, Equatable {
    /// The event's phase.
    public var phase: SwipePhase
    /// Momentum scrolling (the fingers already lifted): ignored.
    public var isMomentum: Bool
    /// `scrollingDeltaX`.
    public var deltaX: CGFloat
    /// `scrollingDeltaY`.
    public var deltaY: CGFloat
    /// `hasPreciseScrollingDeltas`: a trackpad or Magic Mouse, not a wheel.
    public var isPrecise: Bool
    /// "Natural scrolling": the deltas already follow the fingers.
    public var isInvertedFromDevice: Bool
    /// The event's time in seconds (velocity).
    public var timestamp: TimeInterval
    /// A sample.
    public init(phase: SwipePhase, isMomentum: Bool, deltaX: CGFloat, deltaY: CGFloat, isPrecise: Bool,
                isInvertedFromDevice: Bool, timestamp: TimeInterval) {
        self.phase = phase; self.isMomentum = isMomentum; self.deltaX = deltaX; self.deltaY = deltaY
        self.isPrecise = isPrecise; self.isInvertedFromDevice = isInvertedFromDevice; self.timestamp = timestamp
    }
}

/// What a sample means for the gesture.
public nonisolated enum SwipeUpdate: Sendable, Equatable {
    /// Live finger travel along the locked axis (pt, +x = right, +y = down). Drive rubber-banding with it.
    case tracking(SwipeAxis, translation: CGFloat)
    /// Threshold crossed (fires ONCE per touch sequence, while the finger is still down → haptic now).
    case committed(SwipeDirection, velocity: CGFloat)
    /// Released below the threshold: snap back (`CrannyMotion.Kind.snapBack`).
    case cancelled
}

/// Turns scroll samples into tracking, one commit per touch sequence, or a cancel (unit-testable, no AppKit).
public nonisolated struct SwipeTracker: Sendable {
    /// The axes this tracker accepts.
    public var axis: SwipeAxis
    /// Commit distances per direction (DESIGN.md `GestureSpec`).
    public var horizontalCommit: CGFloat = GestureSpec.trackSwipeCommit
    /// Distance that commits a swipe down.
    public var downCommit: CGFloat = GestureSpec.pullOpen
    /// Distance that commits a swipe up.
    public var upCommit: CGFloat = GestureSpec.pushClose
    /// Release speed (pt/s) that commits a short horizontal swipe.
    public var horizontalVelocity: CGFloat = GestureSpec.trackSwipeVelocity
    /// Release speed (pt/s) that commits a short vertical swipe.
    public var verticalVelocity: CGFloat = GestureSpec.verticalVelocity
    /// Settings ▸ Gestures ▸ Sensitivity (0.5…1.5): divides the distances.
    public var sensitivity: CGFloat = 1
    /// Gestures ▸ Invert track swipe.
    public var invertHorizontal = false

    private var x: CGFloat = 0, y: CGFloat = 0
    private var locked: SwipeAxis?
    private var fired = false
    private var lastFire: TimeInterval = -.infinity
    private var lastSample: (t: TimeInterval, x: CGFloat, y: CGFloat)?
    private var previousSample: (t: TimeInterval, x: CGFloat, y: CGFloat)?

    /// A tracker with the DESIGN.md distances.
    public init(axis: SwipeAxis) { self.axis = axis }

    /// Feeds one sample; nil when it changes nothing visible.
    public mutating func handle(_ s: ScrollSample) -> SwipeUpdate? {
        guard !s.isMomentum, s.isPrecise, !s.phase.isEmpty else { return nil }
        if s.phase.contains(.began) || s.phase.contains(.mayBegin) { reset() }
        if s.phase.contains(.ended) || s.phase.contains(.cancelled) {
            defer { reset() }
            guard !fired, let locked else { return nil }   // already committed, or never locked to an axis
            let v = velocity(at: s.timestamp)
            if let dir = direction(for: locked, distance: locked == .horizontal ? x : y),
               abs(locked == .horizontal ? v.x : v.y) >= (locked == .horizontal ? horizontalVelocity : verticalVelocity),
               s.timestamp - lastFire >= GestureSpec.cooldown {
                lastFire = s.timestamp
                return .committed(dir, velocity: locked == .horizontal ? v.x : v.y)
            }
            return .cancelled
        }
        guard s.phase.contains(.changed) || s.phase.contains(.began) else { return nil }
        let sign: CGFloat = s.isInvertedFromDevice ? 1 : -1      // normalise to physical finger motion
        x += s.deltaX * sign; y += s.deltaY * sign
        previousSample = lastSample
        lastSample = (s.timestamp, x, y)
        if locked == nil {
            if abs(x) >= 4, abs(x) >= abs(y) * GestureSpec.axisLock, axis != .vertical { locked = .horizontal }
            else if abs(y) >= 4, abs(y) >= abs(x) * GestureSpec.axisLock, axis != .horizontal { locked = .vertical }
        }
        guard let locked else { return nil }
        let d = locked == .horizontal ? x : y
        if !fired, s.timestamp - lastFire >= GestureSpec.cooldown, let dir = direction(for: locked, distance: d),
           abs(d) >= commitDistance(dir) / max(sensitivity, 0.1) {
            fired = true; lastFire = s.timestamp
            let v = velocity(at: s.timestamp)
            return .committed(dir, velocity: locked == .horizontal ? v.x : v.y)
        }
        return fired ? nil : .tracking(locked, translation: d)
    }

    private func direction(for axis: SwipeAxis, distance d: CGFloat) -> SwipeDirection? {
        guard d != 0 else { return nil }
        switch axis {
        case .horizontal:
            var right = d > 0
            if invertHorizontal { right.toggle() }
            return right ? .right : .left
        case .vertical: return d > 0 ? .down : .up
        case .any: return nil
        }
    }
    private func commitDistance(_ dir: SwipeDirection) -> CGFloat {
        switch dir {
        case .left, .right: horizontalCommit
        case .down: downCommit
        case .up: upCommit
        }
    }
    /// pt/s between the two most recent samples (precise deltas arrive at display rate).
    private func velocity(at t: TimeInterval) -> (x: CGFloat, y: CGFloat) {
        guard let last = lastSample, let prev = previousSample else { return (0, 0) }
        let dt = max(last.t - prev.t, 0.001)
        return ((last.x - prev.x) / dt, (last.y - prev.y) / dt)
    }
    private mutating func reset() {
        x = 0; y = 0; locked = nil; fired = false; lastSample = nil; previousSample = nil
    }
}

public extension SwipeTracker {
    /// A tracker that never commits (no distance or velocity is enough): the recognizer of continuous scroll zones
    /// (`crannyContinuousScrollZone`).
    static func continuous(axis: SwipeAxis) -> SwipeTracker {
        var tracker = SwipeTracker(axis: axis)
        tracker.horizontalCommit = .infinity
        tracker.downCommit = .infinity
        tracker.upCommit = .infinity
        tracker.horizontalVelocity = .infinity
        tracker.verticalVelocity = .infinity
        return tracker
    }
}
