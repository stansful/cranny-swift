// CrannyCore/Input/NotchZones.swift
// AppKit owns drag-and-drop and scroll events for the panel (R1 §5–6: SwiftUI .onDrop registers
// public.data/public.item and .onDrag hands out temporary copies). Views DECLARE zones; the shell's
// root NSView routes events to them by geometry. One registry per canvas (per display panel).
import SwiftUI
import UniformTypeIdentifiers

/// Files dropped on the notch. File promises (Photos, Mail, Safari) are already resolved to URLs
/// by the shell (in a temporary directory) before a handler is called.
public nonisolated struct DropPayload: Sendable {
    /// The dropped files (promises already resolved into a temporary folder).
    public var fileURLs: [URL]
    /// The types on the drag pasteboard.
    public var contentTypes: [UTType]
    /// A payload.
    public init(fileURLs: [URL], contentTypes: [UTType]) { self.fileURLs = fileURLs; self.contentTypes = contentTypes }
}

/// The drop and scroll zones of one canvas. Views declare them (`crannyDropZone`, `crannyScrollZone`); the shell
/// feeds drags and scroll events in and the zones receive them by geometry.
@MainActor @Observable public final class NotchZones {
    /// A file drop target.
    public struct DropZone {
        /// The zone's identifier.
        public let id: DropZoneID
        /// Where it is, in `NotchCoordinateSpace.name`.
        public var frame: CGRect
        /// The types it takes (a drag must conform to one).
        public let accepts: [UTType]
        /// Takes the drop; true when it kept it.
        public let perform: @MainActor (DropPayload) async -> Bool
    }
    /// A two-finger scroll target.
    public struct ScrollZone {
        /// The zone's identifier.
        public let id: ScrollZoneID
        /// Where it is, in `NotchCoordinateSpace.name`.
        public var frame: CGRect
        /// The axis it reacts to.
        public let axis: SwipeAxis
        /// Receives tracking, commit and cancel updates.
        public let onUpdate: @MainActor (SwipeUpdate) -> Void
        /// false = a value zone (`crannyContinuousScrollZone`): never commits, `.tracking` for the whole touch.
        public var commits = true
    }

    /// The drop zone under the pointer during a file drag (views highlight when `armedDropZone == id`).
    public private(set) var armedDropZone: DropZoneID?
    /// Types on the drag pasteboard while a file drag is in progress, else empty.
    public private(set) var draggedTypes: [UTType] = []
    @ObservationIgnored private var dropZones: [DropZoneID: DropZone] = [:]
    @ObservationIgnored private var scrollZones: [ScrollZoneID: ScrollZone] = [:]
    @ObservationIgnored private var trackers: [ScrollZoneID: SwipeTracker] = [:]
    @ObservationIgnored private var activeScrollZone: ScrollZoneID?

    /// An empty registry (one per canvas).
    public init() {}

    // MARK: View side (via modifiers)
    /// Adds or moves a drop zone (from `crannyDropZone`).
    public func setDropZone(_ zone: DropZone) { dropZones[zone.id] = zone }
    /// Removes a drop zone (its view disappeared).
    public func removeDropZone(_ id: DropZoneID) { dropZones[id] = nil; if armedDropZone == id { armedDropZone = nil } }
    /// Adds or moves a scroll zone (from `crannyScrollZone`).
    public func setScrollZone(_ zone: ScrollZone) { scrollZones[zone.id] = zone }
    /// Removes a scroll zone and its gesture state.
    public func removeScrollZone(_ id: ScrollZoneID) { scrollZones[id] = nil; trackers[id] = nil }

    // MARK: Shell side (NotchRootView: NSDraggingDestination + NotchPanel.sendEvent)
    /// A file drag moved: arms the innermost zone under `point` that accepts `types`.
    public func dragUpdated(at point: CGPoint, types: [UTType]) {
        draggedTypes = types
        armedDropZone = dropZones.values
            .filter { $0.frame.contains(point) && $0.accepts.contains { a in types.contains { $0.conforms(to: a) } } }
            .min { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }?.id   // innermost wins
    }
    /// The drag left or ended without a drop.
    public func dragEnded() { draggedTypes = []; armedDropZone = nil }
    /// Delivers to the armed zone, else to `fallback` (normally `.trayKeep`). Returns false if nobody took it.
    public func performDrop(_ payload: DropPayload, fallback: DropZoneID? = .trayKeep) async -> Bool {
        let target = armedDropZone.flatMap { dropZones[$0] } ?? fallback.flatMap { dropZones[$0] }
        dragEnded()
        guard let target else { return false }
        return await target.perform(payload)
    }
    /// Feeds a scroll event to the zone under the pointer. Returns true if consumed.
    public func scroll(_ sample: ScrollSample, at point: CGPoint) -> Bool {
        if sample.phase.contains(.began) || sample.phase.contains(.mayBegin) || activeScrollZone == nil {
            activeScrollZone = scrollZones.values.first { $0.frame.contains(point) }?.id
        }
        guard let id = activeScrollZone, let zone = scrollZones[id] else { return false }
        var tracker = trackers[id] ?? (zone.commits ? SwipeTracker(axis: zone.axis) : .continuous(axis: zone.axis))
        let update = tracker.handle(sample)
        trackers[id] = tracker
        if let update { zone.onUpdate(update) }
        if sample.phase.contains(.ended) || sample.phase.contains(.cancelled) { activeScrollZone = nil }
        return true
    }
}

public extension View {
    /// Declares a file drop target (Tray keep zone, AirDrop widget, pipeline zones, Quick Apps).
    func crannyDropZone(_ id: DropZoneID, accepts: [UTType],
                        perform: @escaping @MainActor (DropPayload) async -> Bool) -> some View {
        modifier(DropZoneModifier(id: id, accepts: accepts, perform: perform))
    }
    /// Declares a two-finger scroll target (track swipe over artwork, timer ±1 min, scrubber seek).
    func crannyScrollZone(_ id: ScrollZoneID, axis: SwipeAxis,
                          onUpdate: @escaping @MainActor (SwipeUpdate) -> Void) -> some View {
        modifier(ScrollZoneModifier(id: id, axis: axis, onUpdate: onUpdate))
    }
    /// Declares a two-finger scroll target for a VALUE (timer ±1 min, a scrubber seek): `.tracking(axis,
    /// translation:)` for every sample of a touch sequence (translation since the touch began, +y = fingers moving
    /// down), `.cancelled` when it ends, never `.committed`. The gesture zones of `crannyScrollZone` commit once per
    /// touch and then go silent, so a long scroll over a value could move it only once; the view turns the travel
    /// into detents. Routing is unchanged (`NotchZones.scroll`, fed by the shell).
    func crannyContinuousScrollZone(_ id: ScrollZoneID, axis: SwipeAxis,
                                    onUpdate: @escaping @MainActor (SwipeUpdate) -> Void) -> some View {
        modifier(ScrollZoneModifier(id: id, axis: axis, onUpdate: onUpdate, commits: false))
    }
}

struct DropZoneModifier: ViewModifier {
    @Environment(\.notchZones) private var zones
    let id: DropZoneID
    let accepts: [UTType]
    let perform: @MainActor (DropPayload) async -> Bool
    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .named(NotchCoordinateSpace.name)) }) { frame in
                zones?.setDropZone(.init(id: id, frame: frame, accepts: accepts, perform: perform))
            }
            .onDisappear { zones?.removeDropZone(id) }
    }
}

struct ScrollZoneModifier: ViewModifier {
    @Environment(\.notchZones) private var zones
    let id: ScrollZoneID
    let axis: SwipeAxis
    let onUpdate: @MainActor (SwipeUpdate) -> Void
    var commits = true
    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .named(NotchCoordinateSpace.name)) }) { frame in
                zones?.setScrollZone(.init(id: id, frame: frame, axis: axis, onUpdate: onUpdate, commits: commits))
            }
            .onDisappear { zones?.removeScrollZone(id) }
    }
}
