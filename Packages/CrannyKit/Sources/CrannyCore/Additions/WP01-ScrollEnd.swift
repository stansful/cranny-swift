// CrannyCore/Additions/WP01-ScrollEnd.swift — additive Core change requested by WP1 (Media): how the touch over a value
// scroll zone ended. `SwipeUpdate.cancelled` means both "the fingers lifted below the threshold" and "the system
// cancelled the gesture" (scroll phase `.cancelled`), so a scrubber could not tell a release (seek to the previewed
// position) from a cancel (seek nowhere). A continuous zone declared with `onEnd:` gets the reason instead of that
// `.cancelled` update. Every other zone, and `SwipeUpdate` itself, is unchanged.
import SwiftUI

extension NotchZones {
    /// How the touch sequence over a scroll zone ended.
    public nonisolated enum ScrollEnd: Sendable, Equatable {
        /// The fingers lifted (scroll phase `.ended`): apply what the scroll previewed.
        case released
        /// The system cancelled the touch sequence (scroll phase `.cancelled`): discard the preview.
        case cancelled

        /// The end that a sample's phase reports; nil while the touch sequence goes on.
        public init?(_ phase: SwipePhase) {
            if phase.contains(.cancelled) {
                self = .cancelled
            } else if phase.contains(.ended) {
                self = .released
            } else {
                return nil
            }
        }
    }
}

public extension View {
    /// A continuous (value) scroll zone that says how each touch ended: `onUpdate` gets `.tracking(axis, translation:)`
    /// for every sample of a touch sequence (never `.committed` or `.cancelled`), then `onEnd` gets `.released` when the
    /// fingers lift or `.cancelled` when the system cancels the touch. A touch that never moved along `axis` reports
    /// nothing, as in every scroll zone.
    func crannyContinuousScrollZone(_ id: ScrollZoneID, axis: SwipeAxis,
                                    onUpdate: @escaping @MainActor (SwipeUpdate) -> Void,
                                    onEnd: @escaping @MainActor (NotchZones.ScrollEnd) -> Void) -> some View {
        modifier(ScrollZoneModifier(id: id, axis: axis, onUpdate: onUpdate, commits: false, onEnd: onEnd))
    }
}
