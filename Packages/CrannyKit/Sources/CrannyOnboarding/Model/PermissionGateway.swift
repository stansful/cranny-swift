// CrannyOnboarding/Model/PermissionGateway.swift — the only door from onboarding to TCC. In the app it is
// Core's `PermissionsCenter` (the one place that queries or requests permissions, ARCHITECTURE.md §3.12);
// tests and previews pass a stand-in, so nothing here can raise a system prompt by accident.
import CrannyCore
import Foundation

@MainActor protocol PermissionGateway: AnyObject {
    /// Never prompts.
    func status(_ kind: PermissionKind) -> PermissionStatus
    /// Shows the system prompt where one exists; called only from an "Allow" button.
    @discardableResult func request(_ kind: PermissionKind) async -> PermissionStatus
    func openSystemSettings(_ kind: PermissionKind)
    /// Re-query every status (when the app becomes active again, e.g. back from System Settings).
    func refresh()
}

extension PermissionsCenter: PermissionGateway {}
