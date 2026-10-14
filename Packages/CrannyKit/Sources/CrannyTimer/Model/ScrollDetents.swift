// CrannyTimer/Model/ScrollDetents.swift — turns the live finger travel of one two-finger scroll over the Timer face
// into ±1-minute detents (DESIGN.md §7.7: "Scrolling over the face adjusts ±1 min, `.levelChange` per detent").
import CoreGraphics

nonisolated struct ScrollDetents: Equatable, Sendable {
    /// Finger travel per detent (pt). Short enough that a relaxed swipe covers several minutes.
    static let defaultStep: CGFloat = 12

    let step: CGFloat
    /// Detents already reported for the current touch sequence.
    private(set) var applied = 0

    init(step: CGFloat = Self.defaultStep) { self.step = max(step, 1) }

    /// `translation` is the travel since the touch began along the locked axis, +y = fingers moving DOWN
    /// (`SwipeUpdate.tracking`). Fingers moving up increase the time. Returns the detents to apply now (signed).
    mutating func update(translation: CGFloat) -> Int {
        let reached = Int((-translation / step).rounded(.towardZero))
        defer { applied = reached }
        return reached - applied
    }

    /// The touch sequence ended (`.cancelled` / `.committed`).
    mutating func reset() { applied = 0 }
}
