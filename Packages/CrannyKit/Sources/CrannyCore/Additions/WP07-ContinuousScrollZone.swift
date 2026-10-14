// CrannyCore/Additions/WP07-ContinuousScrollZone.swift — additive Core change of WP7 (Timer).
// A scroll zone for VALUES (timer ±1 min, a scrubber seek): the gesture zones of `crannyScrollZone` commit once per
// touch (track swipes) and then go silent, so a long scroll over a value could move it only once. A continuous zone
// never commits: it reports `.tracking` for the whole touch sequence and `.cancelled` when the fingers lift; the
// view turns the travel into detents. Routing is unchanged (`NotchZones.scroll`, fed by the shell).
import SwiftUI

public extension View {
    /// Declares a two-finger scroll target for a value: `.tracking(axis, translation:)` for every sample of a touch
    /// sequence (translation since the touch began, +y = fingers moving down), `.cancelled` when it ends. Never
    /// `.committed`.
    func crannyContinuousScrollZone(_ id: ScrollZoneID, axis: SwipeAxis,
                                    onUpdate: @escaping @MainActor (SwipeUpdate) -> Void) -> some View {
        modifier(ScrollZoneModifier(id: id, axis: axis, onUpdate: onUpdate, commits: false))
    }
}

public extension SwipeTracker {
    /// A tracker that never commits (no distance or velocity is enough): the recognizer of continuous scroll zones.
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
