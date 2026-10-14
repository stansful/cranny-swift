// CrannyMirror/Camera/CameraAuthorization.swift — camera permission, behind a seam so tests never reach TCC.
// The live implementation goes through `PermissionsCenter`, the only code that queries or requests TCC
// (ARCHITECTURE.md §3.12). The prompt is shown only after a click on the widget (DESIGN.md §6.8, §7.4).
import CrannyCore

@MainActor protocol CameraAuthorizing: AnyObject {
    /// The current status. Reading it never prompts; it is observable, so views follow changes.
    var status: PermissionStatus { get }
    /// Re-reads the status from the system. `force` re-reads even a cached grant (after access was revoked).
    /// The live implementation re-queries every permission (`PermissionsCenter.refresh`), so the model calls it
    /// only on a click and, for a while, after the "Allow…" chip opened System Settings — never on every panel
    /// open.
    func refresh(force: Bool)
    /// Shows the system prompt where one exists and returns the answer.
    func request() async -> PermissionStatus
    /// System Settings ▸ Privacy & Security ▸ Camera.
    func openSystemSettings()
}

/// `PermissionsCenter`-backed camera permission.
final class PermissionsCenterAuthorization: CameraAuthorizing {
    private let center: PermissionsCenter

    init(center: PermissionsCenter) { self.center = center }

    var status: PermissionStatus { center.status(.camera) }

    /// `PermissionsCenter` caches statuses. A grant only changes by the user's hand in System Settings, so the
    /// cache is re-read when it is not a grant (the user may have just allowed it) or when forced.
    func refresh(force: Bool) {
        if force || center.status(.camera) != .granted { center.refresh() }
    }

    func request() async -> PermissionStatus { await center.request(.camera) }

    func openSystemSettings() { center.openSystemSettings(.camera) }
}
