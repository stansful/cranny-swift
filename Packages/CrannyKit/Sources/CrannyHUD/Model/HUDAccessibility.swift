// CrannyHUD/Model/HUDAccessibility.swift — how the HUD reads the Accessibility grant (ARCHITECTURE.md §7.1, §7.13).
// macOS posts no notification when the grant changes. The controller therefore compares the cached status with a
// live `AXIsProcessTrusted()` when the user comes back to Cranny and when macOS disables the key tap, and refreshes
// the cache when they differ: granted in System Settings, or revoked while the tap ran. Nothing here prompts.
import ApplicationServices
import CrannyCore

/// The Accessibility grant as `HUDController` sees it (tests inject their own).
struct HUDAccessibility {
    /// The cached status (`PermissionsCenter.statuses`, observable): what the tap config follows.
    var isGranted: @MainActor () -> Bool
    /// macOS's answer right now (`AXIsProcessTrusted`: one cheap call, never a prompt).
    var isTrustedNow: @MainActor () -> Bool
    /// Re-reads the cached statuses (Settings ▸ HUD and the config follow by observation).
    var refresh: @MainActor () -> Void

    /// The app's permissions center.
    static func live(_ permissions: PermissionsCenter) -> HUDAccessibility {
        HUDAccessibility(isGranted: { permissions.status(.accessibility) == .granted },
                         isTrustedNow: { AXIsProcessTrusted() },
                         refresh: { permissions.refresh() })
    }

    /// The cache disagrees with macOS, in either direction.
    var isStale: Bool { isTrustedNow() != isGranted() }
}
