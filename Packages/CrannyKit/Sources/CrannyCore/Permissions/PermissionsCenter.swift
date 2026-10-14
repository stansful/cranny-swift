// CrannyCore/Permissions/PermissionsCenter.swift
// The ONLY place that queries or requests TCC permissions (R3 §11). Modules call `request` from the
// inline "needs permission" state of their widget — never at launch, never in bulk.
import AppKit
import ApplicationServices
import AVFoundation
import CoreBluetooth
import CoreServices
import EventKit
import Observation

/// A privacy permission a module may ask for (declared with `registry.declare(_:reason:)`).
public nonisolated enum PermissionKind: Hashable, Codable, Sendable {
    case accessibility                  // HUD key interception (CGEventTap on NX_SYSDEFINED)
    case calendar                       // EventKit full access
    case camera                         // Mirror
    case bluetooth                      // optional "Show all Bluetooth devices" (IOBluetooth)
    case systemAudioRecording           // optional Live visualizer (Core Audio process tap, macOS 14.2+)
    case automation(bundleID: String)   // Apple Events to Music / Spotify (media fallback)

    /// System Settings deep link (scheme verified on macOS 27; anchors UNVERIFIED there).
    public var settingsURL: URL? {
        let base = "x-apple.systempreferences:com.apple.preference.security?"
        return switch self {
        case .accessibility: URL(string: base + "Privacy_Accessibility")
        case .calendar: URL(string: base + "Privacy_Calendars")
        case .camera: URL(string: base + "Privacy_Camera")
        case .bluetooth: URL(string: base + "Privacy_Bluetooth")
        case .systemAudioRecording: URL(string: base + "Privacy_ScreenCapture")
        case .automation: URL(string: base + "Privacy_Automation")
        }
    }
}

/// What macOS says about a permission (Settings shows it with `PermissionStatusPill`).
public nonisolated enum PermissionStatus: String, Codable, Sendable {
    case notDetermined, granted, denied, restricted
    /// No query API (system audio recording) or the automation target is not running.
    case unknown
}

/// The one place that queries and requests permissions (`services.permissions`). Requests come only from an explicit
/// user action (a widget's permission state, Settings ▸ Permissions, onboarding).
@MainActor @Observable public final class PermissionsCenter {
    /// The last known status of each permission (observable).
    public private(set) var statuses: [PermissionKind: PermissionStatus] = [:]
    @ObservationIgnored private var accessibilityWatch: Task<Void, Never>?
    @ObservationIgnored private var recorded: [PermissionKind: PermissionStatus] = [:]

    /// Queries every permission once (cheap, never prompts).
    public init() { refresh() }

    /// The last known status, querying it if it was never asked for.
    public func status(_ kind: PermissionKind) -> PermissionStatus {
        statuses[kind] ?? query(kind)
    }

    /// Re-query everything (call on app activation and when Settings ▸ Permissions appears).
    public func refresh() {
        var next: [PermissionKind: PermissionStatus] = [:]
        for kind in [PermissionKind.accessibility, .calendar, .camera, .bluetooth, .systemAudioRecording] {
            next[kind] = query(kind)
        }
        for (kind, _) in statuses { if case .automation = kind { next[kind] = query(kind) } }
        statuses = next
    }

    /// Shows the system prompt when one exists; otherwise opens System Settings. Returns the new status.
    @discardableResult
    public func request(_ kind: PermissionKind) async -> PermissionStatus {
        switch kind {
        case .accessibility:
            // kAXTrustedCheckOptionPrompt is a mutable C global (Swift 6 error) — use its literal value.
            _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
            watchAccessibility()
        case .calendar:
            _ = try? await EKEventStore().requestFullAccessToEvents()
        case .camera:
            _ = await AVCaptureDevice.requestAccess(for: .video)
        case .bluetooth:
            await BluetoothPrompt.trigger()
        case .systemAudioRecording:
            break   // prompted by AudioDeviceStart in CrannyMedia; it reports back via `record`
        case .automation(let bundleID):
            _ = await Self.automationStatus(bundleID, ask: true)
        }
        let s = query(kind)
        statuses[kind] = s
        return s
    }

    /// Opens the permission's page of Privacy & Security in System Settings.
    public func openSystemSettings(_ kind: PermissionKind) {
        if let url = kind.settingsURL { NSWorkspace.shared.open(url) }
    }

    /// For kinds without a query API: the feature reports what it observed (tap delivered audio → granted).
    public func record(_ status: PermissionStatus, for kind: PermissionKind) {
        recorded[kind] = status
        statuses[kind] = status
    }

    // MARK: Queries (cheap, never prompt)
    private func query(_ kind: PermissionKind) -> PermissionStatus {
        switch kind {
        case .accessibility:
            return AXIsProcessTrusted() ? .granted : .notDetermined
        case .calendar:
            return switch EKEventStore.authorizationStatus(for: .event) {
            case .fullAccess: .granted
            case .denied, .writeOnly: .denied
            case .restricted: .restricted
            case .notDetermined: .notDetermined
            @unknown default: .unknown
            }
        case .camera:
            return switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized: .granted
            case .denied: .denied
            case .restricted: .restricted
            case .notDetermined: .notDetermined
            @unknown default: .unknown
            }
        case .bluetooth:
            return switch CBManager.authorization {
            case .allowedAlways: .granted
            case .denied: .denied
            case .restricted: .restricted
            case .notDetermined: .notDetermined
            @unknown default: .unknown
            }
        case .systemAudioRecording:
            return recorded[kind] ?? .unknown
        case .automation(let bundleID):
            return Self.automationStatusSync(bundleID)
        }
    }

    /// Accessibility changes do not notify: poll every 1.5 s for up to 2 minutes after a request.
    private func watchAccessibility() {
        accessibilityWatch?.cancel()
        accessibilityWatch = Task { [weak self] in
            for _ in 0..<80 {
                try? await Task.sleep(for: .milliseconds(1500))
                guard let self, !Task.isCancelled else { return }
                if AXIsProcessTrusted() { self.statuses[.accessibility] = .granted; return }
            }
        }
    }

    private static func automationStatusSync(_ bundleID: String) -> PermissionStatus {
        map(automationOSStatus(bundleID, ask: false))
    }
    /// `AEDeterminePermissionToAutomateTarget` blocks while its prompt is up: never on the main thread.
    @concurrent private static func automationStatus(_ bundleID: String, ask: Bool) async -> PermissionStatus {
        map(automationOSStatus(bundleID, ask: ask))
    }
    nonisolated private static func automationOSStatus(_ bundleID: String, ask: Bool) -> OSStatus {
        let target = NSAppleEventDescriptor(bundleIdentifier: bundleID)
        guard let desc = target.aeDesc else { return OSStatus(procNotFound) }
        return AEDeterminePermissionToAutomateTarget(desc, typeWildCard, typeWildCard, ask)
    }
    nonisolated private static func map(_ status: OSStatus) -> PermissionStatus {
        switch status {
        case noErr: .granted
        case OSStatus(errAEEventNotPermitted): .denied
        case OSStatus(errAEEventWouldRequireUserConsent): .notDetermined
        default: .unknown          // procNotFound (-600): the player is not running
        }
    }
}

/// Creating a CBCentralManager is what shows the Bluetooth prompt.
@MainActor private enum BluetoothPrompt {
    static var manager: CBCentralManager?
    static func trigger() async {
        guard CBManager.authorization == .notDetermined else { return }
        manager = CBCentralManager(delegate: nil, queue: nil)
        for _ in 0..<60 where CBManager.authorization == .notDetermined {
            try? await Task.sleep(for: .milliseconds(500))
        }
        manager = nil
    }
}
