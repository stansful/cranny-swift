// CrannyOnboarding/Model/GesturePractice.swift — step 3's practice notch (pure). Two-finger scrolls over the
// stage go through Core's `SwipeTracker` exactly like the real panel (DESIGN.md §4.4): pull down opens with
// rubber-banding, push up closes, a sideways swipe changes the (sample) track. Nothing reaches real media.
import CoreGraphics
import CrannyCore
import Foundation

nonisolated struct GesturePractice: Sendable {
    /// What the stage should do for one scroll sample.
    enum Effect: Equatable, Sendable {
        /// Rubber-banded offset of the gesture in progress (pt, +y = down); `.zero` ends it.
        case follow(CGSize)
        /// The pull crossed its threshold: open the practice notch (haptic now, the finger is still down).
        case open
        /// The push crossed its threshold: close it.
        case close
        /// A sideways swipe crossed its threshold over the sample track.
        case track(ActivityGesture)
        /// Released short of the threshold: snap back.
        case snapBack
    }

    private(set) var isOpen = false
    /// Sideways swipes are practised only while something plays (DESIGN.md §12.1).
    var allowsTrackSwipe: Bool
    private var tracker = SwipeTracker(axis: .any)

    init(allowsTrackSwipe: Bool, sensitivity: Double = 1, invertsTrackSwipe: Bool = false) {
        self.allowsTrackSwipe = allowsTrackSwipe
        tracker.sensitivity = CGFloat(min(max(sensitivity, 0.5), 1.5))
        tracker.invertHorizontal = invertsTrackSwipe
    }

    mutating func handle(_ sample: ScrollSample) -> [Effect] {
        guard let update = tracker.handle(sample) else { return [] }
        switch update {
        case .tracking(.vertical, let translation):
            // Only the way that does something moves the shape; a pull that comes back past where it started
            // rests at zero (it never stays at its last small offset).
            let useful = isOpen ? min(translation, 0) : max(translation, 0)
            return [.follow(CGSize(width: 0, height: CrannyMotion.rubberBand(useful, limit: GestureSpec.verticalTravel)))]
        case .tracking(.horizontal, let translation):
            guard !isOpen, allowsTrackSwipe else { return [] }
            return [.follow(CGSize(width: CrannyMotion.rubberBand(translation, limit: GestureSpec.horizontalTravel), height: 0))]
        case .tracking(.any, _):
            return []
        case .committed(.down, _):
            guard !isOpen else { return [] }
            isOpen = true
            return [.follow(.zero), .open]
        case .committed(.up, _):
            guard isOpen else { return [] }
            isOpen = false
            return [.follow(.zero), .close]
        case .committed(let direction, _):
            guard !isOpen, allowsTrackSwipe else { return [] }
            return [.follow(.zero), .track(direction == .left ? .swipeLeft : .swipeRight)]
        case .cancelled:
            return [.snapBack]
        }
    }

    /// The stage was reset (step re-entered).
    mutating func reset() { isOpen = false }
}
