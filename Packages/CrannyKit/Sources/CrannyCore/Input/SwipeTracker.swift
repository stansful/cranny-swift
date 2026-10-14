// CrannyCore/Input/SwipeTracker.swift
// Pure two-finger swipe state machine (extends R1 §6's verified recognizer with live tracking for
// rubber-banding, DESIGN.md §4.4). No AppKit state: unit-test it with synthetic samples.
import CoreGraphics
import Foundation

public nonisolated enum SwipeAxis: Sendable, Equatable { case horizontal, vertical, any }
public nonisolated enum SwipeDirection: Sendable, Equatable { case left, right, up, down }

/// Scroll phases (mirrors NSEvent.Phase without importing AppKit).
public nonisolated struct SwipePhase: OptionSet, Sendable, Hashable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let began = SwipePhase(rawValue: 1 << 0)
    public static let stationary = SwipePhase(rawValue: 1 << 1)
    public static let changed = SwipePhase(rawValue: 1 << 2)
    public static let ended = SwipePhase(rawValue: 1 << 3)
    public static let cancelled = SwipePhase(rawValue: 1 << 4)
    public static let mayBegin = SwipePhase(rawValue: 1 << 5)
}

public nonisolated struct ScrollSample: Sendable, Equatable {
    public var phase: SwipePhase
    public var isMomentum: Bool            // momentumPhase non-empty: fingers already lifted → ignored
    public var deltaX: CGFloat             // scrollingDeltaX
    public var deltaY: CGFloat             // scrollingDeltaY
    public var isPrecise: Bool             // hasPreciseScrollingDeltas (trackpad, Magic Mouse)
    public var isInvertedFromDevice: Bool  // "natural scrolling": deltas already follow the fingers
    public var timestamp: TimeInterval
    public init(phase: SwipePhase, isMomentum: Bool, deltaX: CGFloat, deltaY: CGFloat, isPrecise: Bool,
                isInvertedFromDevice: Bool, timestamp: TimeInterval) {
        self.phase = phase; self.isMomentum = isMomentum; self.deltaX = deltaX; self.deltaY = deltaY
        self.isPrecise = isPrecise; self.isInvertedFromDevice = isInvertedFromDevice; self.timestamp = timestamp
    }
}

public nonisolated enum SwipeUpdate: Sendable, Equatable {
    /// Live finger travel along the locked axis (pt, +x = right, +y = down). Drive rubber-banding with it.
    case tracking(SwipeAxis, translation: CGFloat)
    /// Threshold crossed (fires ONCE per touch sequence, while the finger is still down → haptic now).
    case committed(SwipeDirection, velocity: CGFloat)
    /// Released below the threshold: snap back (`CrannyMotion.Kind.snapBack`).
    case cancelled
}

public nonisolated struct SwipeTracker: Sendable {
    public var axis: SwipeAxis
    /// Commit distances per direction (DESIGN.md `GestureSpec`).
    public var horizontalCommit: CGFloat = GestureSpec.trackSwipeCommit
    public var downCommit: CGFloat = GestureSpec.pullOpen
    public var upCommit: CGFloat = GestureSpec.pushClose
    public var horizontalVelocity: CGFloat = GestureSpec.trackSwipeVelocity
    public var verticalVelocity: CGFloat = GestureSpec.verticalVelocity
    /// Settings ▸ Gestures ▸ Sensitivity (0.5…1.5): divides the distances.
    public var sensitivity: CGFloat = 1
    public var invertHorizontal = false

    private var x: CGFloat = 0, y: CGFloat = 0
    private var locked: SwipeAxis?
    private var fired = false
    private var lastFire: TimeInterval = -.infinity
    private var lastSample: (t: TimeInterval, x: CGFloat, y: CGFloat)?
    private var previousSample: (t: TimeInterval, x: CGFloat, y: CGFloat)?

    public init(axis: SwipeAxis) { self.axis = axis }

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
