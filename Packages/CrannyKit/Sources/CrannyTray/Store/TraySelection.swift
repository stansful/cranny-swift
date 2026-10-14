// CrannyTray/Store/TraySelection.swift — Finder-style selection of tray tiles (DESIGN.md §8.1 "Interaction",
// §16 keyboard map): click, ⌘-click, ⇧-click, ⌘A, arrows and ⇧-arrows. A pure value; the store owns one.
import Foundation

nonisolated struct TraySelection: Equatable, Sendable {
    /// Modifier keys of a click that matter for selection.
    struct Modifiers: OptionSet, Sendable {
        let rawValue: Int
        static let command = Modifiers(rawValue: 1 << 0)
        static let shift = Modifiers(rawValue: 1 << 1)
    }

    private(set) var selected: Set<UUID> = []
    /// Where ⇧-click and ⇧-arrows extend from.
    private(set) var anchor: UUID?
    /// The tile the keyboard is on (focus ring).
    private(set) var cursor: UUID?

    var isEmpty: Bool { selected.isEmpty }
    func contains(_ id: UUID) -> Bool { selected.contains(id) }
    /// The selected ids in tray order.
    func ordered(in order: [UUID]) -> [UUID] { order.filter(selected.contains) }

    /// A click on `id`. `order` is the tray's visible order.
    mutating func click(_ id: UUID, modifiers: Modifiers, order: [UUID]) {
        if modifiers.contains(.shift), let anchor, let range = Self.range(anchor, id, in: order) {
            selected = modifiers.contains(.command) ? selected.union(range) : Set(range)
        } else if modifiers.contains(.command) {
            if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
            anchor = id
        } else {
            selected = [id]
            anchor = id
        }
        cursor = id
    }

    /// ⌘A.
    mutating func selectAll(_ order: [UUID]) {
        selected = Set(order)
        anchor = order.first
        cursor = cursor ?? order.first
    }

    /// ← / → (with ⇧ to extend). With nothing selected, the first arrow selects the first (or last) tile.
    mutating func move(forward: Bool, extend: Bool, order: [UUID]) {
        guard !order.isEmpty else { return }
        guard let current = cursor, let index = order.firstIndex(of: current) else {
            let start = forward ? order[0] : order[order.count - 1]
            selected = [start]; anchor = start; cursor = start
            return
        }
        let next = order[min(max(index + (forward ? 1 : -1), 0), order.count - 1)]
        cursor = next
        if extend, let anchor, let range = Self.range(anchor, next, in: order) {
            selected = Set(range)
        } else {
            selected = [next]
            anchor = next
        }
    }

    mutating func clear() { selected = []; anchor = nil; cursor = nil }

    /// Drops ids that are no longer in the tray (after a removal).
    mutating func prune(to order: [UUID]) {
        let existing = Set(order)
        selected.formIntersection(existing)
        if let a = anchor, !existing.contains(a) { anchor = nil }
        if let c = cursor, !existing.contains(c) { cursor = nil }
    }

    /// Replaces the selection (results of a pipeline become selected so they can be chained).
    mutating func set(_ ids: [UUID]) {
        selected = Set(ids); anchor = ids.first; cursor = ids.first
    }

    private static func range(_ a: UUID, _ b: UUID, in order: [UUID]) -> ArraySlice<UUID>? {
        guard let i = order.firstIndex(of: a), let j = order.firstIndex(of: b) else { return nil }
        return order[min(i, j)...max(i, j)]
    }
}
