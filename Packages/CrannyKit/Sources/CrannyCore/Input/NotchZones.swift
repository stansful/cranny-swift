// CrannyCore/Input/NotchZones.swift
// AppKit owns drag-and-drop and scroll events for the panel (R1 §5–6: SwiftUI .onDrop registers
// public.data/public.item and .onDrag hands out temporary copies). Views DECLARE zones; the shell's
// root NSView routes events to them by geometry. One registry per canvas (per display panel).
import SwiftUI
import UniformTypeIdentifiers

/// Files dropped on the notch. File promises (Photos, Mail, Safari) are already resolved to URLs
/// by the shell (in a temporary directory) before a handler is called.
public nonisolated struct DropPayload: Sendable {
    public var fileURLs: [URL]
    public var contentTypes: [UTType]
    public init(fileURLs: [URL], contentTypes: [UTType]) { self.fileURLs = fileURLs; self.contentTypes = contentTypes }
}

@MainActor @Observable public final class NotchZones {
    public struct DropZone {
        public let id: DropZoneID
        public var frame: CGRect                         // in NotchCoordinateSpace.name
        public let accepts: [UTType]
        public let perform: @MainActor (DropPayload) async -> Bool
    }
    public struct ScrollZone {
        public let id: ScrollZoneID
        public var frame: CGRect
        public let axis: SwipeAxis
        public let onUpdate: @MainActor (SwipeUpdate) -> Void
    }

    /// The drop zone under the pointer during a file drag (views highlight when `armedDropZone == id`).
    public private(set) var armedDropZone: DropZoneID?
    /// Types on the drag pasteboard while a file drag is in progress, else empty.
    public private(set) var draggedTypes: [UTType] = []
    @ObservationIgnored private var dropZones: [DropZoneID: DropZone] = [:]
    @ObservationIgnored private var scrollZones: [ScrollZoneID: ScrollZone] = [:]
    @ObservationIgnored private var trackers: [ScrollZoneID: SwipeTracker] = [:]
    @ObservationIgnored private var activeScrollZone: ScrollZoneID?

    public init() {}

    // MARK: View side (via modifiers)
    public func setDropZone(_ zone: DropZone) { dropZones[zone.id] = zone }
    public func removeDropZone(_ id: DropZoneID) { dropZones[id] = nil; if armedDropZone == id { armedDropZone = nil } }
    public func setScrollZone(_ zone: ScrollZone) { scrollZones[zone.id] = zone }
    public func removeScrollZone(_ id: ScrollZoneID) { scrollZones[id] = nil; trackers[id] = nil }

    // MARK: Shell side (NotchRootView: NSDraggingDestination + NotchPanel.sendEvent)
    public func dragUpdated(at point: CGPoint, types: [UTType]) {
        draggedTypes = types
        armedDropZone = dropZones.values
            .filter { $0.frame.contains(point) && $0.accepts.contains { a in types.contains { $0.conforms(to: a) } } }
            .min { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }?.id   // innermost wins
    }
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
        var tracker = trackers[id] ?? SwipeTracker(axis: zone.axis)
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
    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .named(NotchCoordinateSpace.name)) }) { frame in
                zones?.setScrollZone(.init(id: id, frame: frame, axis: axis, onUpdate: onUpdate))
            }
            .onDisappear { zones?.removeScrollZone(id) }
    }
}
