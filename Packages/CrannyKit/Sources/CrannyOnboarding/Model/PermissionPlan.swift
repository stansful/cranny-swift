// CrannyOnboarding/Model/PermissionPlan.swift — step 5: one row per permission the chosen layout needs,
// built from what modules declared (`registry.permissionUses`). Pure. DESIGN.md §12.1: Calendar,
// Accessibility (HUD), Automation (media apps), Bluetooth; Camera is never asked here (Mirror asks on first
// use) and System Audio Recording has no prompt to show (CrannyMedia records what it observes). A use that
// serves an off-by-default switch (`PermissionUse.optIn`: Media's Apple Events fallback for Automation, every
// Bluetooth device for Bluetooth) is offered only while that switch is on: otherwise the grant would change
// nothing, and the switch in Settings asks for the permission when it is turned on. An Automation use counts only
// while its app is installed (`isAvailable`: Core's `AppIdentityResolver`), as in Settings ▸ Permissions.
import CrannyCore
import Foundation

/// A row of step 5. Several kinds can share a row (Automation for each media app).
nonisolated enum PermissionGroup: Int, CaseIterable, Comparable, Sendable {
    case calendar, accessibility, automation, bluetooth

    /// nil for kinds onboarding never asks for.
    init?(_ kind: PermissionKind) {
        switch kind {
        case .calendar: self = .calendar
        case .accessibility: self = .accessibility
        case .automation: self = .automation
        case .bluetooth: self = .bluetooth
        case .camera, .systemAudioRecording: return nil
        }
    }

    /// DESIGN.md §14.1 symbols (`accessibility` is Apple's Accessibility feature, its restricted meaning).
    var symbol: String {
        switch self {
        case .calendar: "calendar"
        case .accessibility: "accessibility"
        case .automation: "music.note"
        case .bluetooth: "headphones"
        }
    }

    static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
}

nonisolated struct PermissionRow: Identifiable, Equatable, Sendable {
    let group: PermissionGroup
    /// Every kind behind the row, in declaration order, without duplicates.
    let kinds: [PermissionKind]
    /// The modules' one-line reasons, without duplicates ("Show your events in Cranny…").
    let reasons: [String]
    var id: PermissionGroup { group }
}

nonisolated enum PermissionPlan {
    /// Features that work with every layout: the HUD and the system activities (battery, devices).
    static let everyLayout: Set<ModuleID> = [.hud, .system]

    /// The modules a layout needs permissions for: its widgets' modules plus `everyLayout`.
    static func modules(for items: [NookItem]) -> Set<ModuleID> {
        PresetLayout.modules(of: items).union(everyLayout)
    }

    /// One row per group, in DESIGN.md's order, for the uses of `modules` that a grant makes work: `isOn` reads
    /// the opt-in switch of a use that has one (`PermissionUse.optIn`), and `isAvailable` drops a kind whose app is
    /// not installed (or not looked up yet).
    static func rows(uses: [PermissionUse], modules: Set<ModuleID>, isOn: (SettingKey<Bool>) -> Bool,
                     isAvailable: (PermissionKind) -> Bool = { _ in true }) -> [PermissionRow] {
        var kinds: [PermissionGroup: [PermissionKind]] = [:]
        var reasons: [PermissionGroup: [String]] = [:]
        for use in uses where modules.contains(use.module) && use.optIn.map(isOn) != false && isAvailable(use.kind) {
            guard let group = PermissionGroup(use.kind) else { continue }
            if !(kinds[group] ?? []).contains(use.kind) { kinds[group, default: []].append(use.kind) }
            let reason = use.reason.trimmingCharacters(in: .whitespacesAndNewlines)
            if !reason.isEmpty, !(reasons[group] ?? []).contains(reason) { reasons[group, default: []].append(reason) }
        }
        return kinds.keys.sorted().map { PermissionRow(group: $0, kinds: kinds[$0] ?? [], reasons: reasons[$0] ?? []) }
    }
}

/// What a row offers, from the statuses of its kinds.
nonisolated enum PermissionRowState: Equatable, Sendable {
    /// "Allow" shows the system prompt.
    case askable
    /// Every kind is granted.
    case granted
    /// Turned off in System Settings: "Open System Settings".
    case denied
    /// A device-management profile decides.
    case restricted
    /// Asked, but the system could not decide yet (an Automation target that is not running): Cranny asks
    /// again when the feature needs it.
    case deferred

    /// `requested`: the person already pressed Allow on this row.
    static func combining(_ statuses: [PermissionStatus], requested: Bool) -> Self {
        guard !statuses.isEmpty else { return .askable }
        if statuses.allSatisfy({ $0 == .granted }) { return .granted }
        if statuses.contains(.notDetermined) { return .askable }
        if statuses.contains(.denied) { return .denied }
        if statuses.contains(.unknown) { return requested ? .deferred : .askable }
        return .restricted
    }
}
