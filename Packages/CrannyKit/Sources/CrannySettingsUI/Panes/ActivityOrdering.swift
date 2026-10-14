// CrannySettingsUI/Panes/ActivityOrdering.swift — the pure logic of Settings ▸ Live Activities (DESIGN.md §9.4, §11.1):
// which kinds are listed (all but the P0 HUD, which has its own pane), the priority classes they sit in, the user's
// order within a class (`CoreSettings.activityOrder` breaks ties only within a class) and the per-kind preferences
// (`CoreSettings.activityPreferences`; a missing entry means the kind's defaults, so writing the defaults removes it).
import CrannyCore
import Foundation
import SwiftUI   // `MutableCollection.move(fromOffsets:toOffset:)`

enum ActivityOrdering {
    /// One priority class and its kinds in display order.
    struct Group: Equatable {
        let priority: ActivityPriority
        let kinds: [ActivityKind]
    }

    /// Kinds listed in Settings: everything except P0 (the HUD is controlled in its own pane, "never two HUDs").
    static func listed(_ kinds: [ActivityKind]) -> [ActivityKind] {
        kinds.filter { $0.defaultPriority != .hud }
    }

    /// Classes in priority order, each sorted by the user's order, then registration order.
    static func groups(_ kinds: [ActivityKind], order: [ActivityID]) -> [Group] {
        let listed = listed(kinds)
        return ActivityPriority.allCases.compactMap { priority in
            let members = listed.enumerated()
                .filter { $0.element.defaultPriority == priority }
                .sorted { (order.firstIndex(of: $0.element.id) ?? .max, $0.offset) < (order.firstIndex(of: $1.element.id) ?? .max, $1.offset) }
                .map(\.element)
            return members.isEmpty ? nil : Group(priority: priority, kinds: members)
        }
    }

    /// The order to store after moving `source` to `destination` within one class (SwiftUI `onMove` semantics);
    /// every listed kind is written, so the result is total and stable.
    static func moving(in groups: [Group], priority: ActivityPriority, from source: IndexSet, to destination: Int) -> [ActivityID] {
        groups.flatMap { group -> [ActivityID] in
            var ids = group.kinds.map(\.id)
            if group.priority == priority { ids.move(fromOffsets: source, toOffset: destination) }
            return ids
        }
    }

    /// Moves one kind up (−1) or down (+1) within its class.
    static func shifting(_ id: ActivityID, by offset: Int, in groups: [Group]) -> [ActivityID] {
        guard let group = groups.first(where: { $0.kinds.contains { $0.id == id } }),
              let index = group.kinds.firstIndex(where: { $0.id == id }) else { return groups.flatMap { $0.kinds.map(\.id) } }
        let target = min(max(index + offset, 0), group.kinds.count - 1)
        guard target != index else { return groups.flatMap { $0.kinds.map(\.id) } }
        return moving(in: groups, priority: group.priority, from: IndexSet(integer: index), to: target > index ? target + 1 : target)
    }

    /// The effective preference of a kind.
    static func preference(_ kind: ActivityKind, in preferences: [ActivityID: ActivityPreference]) -> ActivityPreference {
        preferences[kind.id] ?? ActivityPreference(isEnabled: kind.isEnabledByDefault, peeksOnChange: kind.peeksOnChangeByDefault)
    }

    /// `preferences` with `kind` set to `preference`; the kind's defaults are stored as "no entry".
    static func setting(_ preference: ActivityPreference, for kind: ActivityKind,
                        in preferences: [ActivityID: ActivityPreference]) -> [ActivityID: ActivityPreference] {
        var next = preferences
        let defaults = ActivityPreference(isEnabled: kind.isEnabledByDefault, peeksOnChange: kind.peeksOnChangeByDefault)
        next[kind.id] = preference == defaults ? nil : preference
        return next
    }
}
