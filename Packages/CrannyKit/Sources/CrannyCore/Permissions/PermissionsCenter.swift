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
///
/// Automation answers are cached per app (§10.20 #27): `AEDeterminePermissionToAutomateTarget` is asked off the main
/// actor, never from a view body, and only again on `refresh()` (Settings appearing, the app becoming active), after a
/// request, or when a caller needs a fresh answer (`currentStatus`). Until an app's first answer lands, `knownStatus`
/// is nil (rows show a spinner) and `status` reads `.unknown`. The other kinds are cheap synchronous queries.
@MainActor @Observable public final class PermissionsCenter {
    /// macOS's Automation answer for one app, computed off the main actor (`@concurrent`: awaiting it returns to the
    /// main actor); `ask` false never prompts. The app uses `systemAutomationStatus`; tests inject a probe that records
    /// its calls.
    public typealias AutomationProbe = @concurrent @Sendable (_ bundleID: String, _ ask: Bool) async -> PermissionStatus

    /// The last known status of each permission (observable).
    public private(set) var statuses: [PermissionKind: PermissionStatus] = [:]
    @ObservationIgnored private var accessibilityWatch: Task<Void, Never>?
    @ObservationIgnored private var recorded: [PermissionKind: PermissionStatus] = [:]
    @ObservationIgnored private let automationProbe: AutomationProbe
    /// Per app, the number of the latest Automation query or answer; an older query that lands later is dropped.
    @ObservationIgnored private var automationGeneration: [String: Int] = [:]
    /// Apps whose first Automation query runs (`knownStatus` starts one at most).
    @ObservationIgnored private var firstQueries: Set<String> = []
    @ObservationIgnored private var activationObserver: (any NSObjectProtocol)?

    /// Queries every permission except Automation once (cheap, never prompts). `automationProbe` answers Automation
    /// questions off the main actor. With `refreshesOnActivation` (the app's one center), every activation of Cranny
    /// refreshes the statuses: the user may have changed them in System Settings meanwhile.
    public init(automationProbe: @escaping AutomationProbe = { await PermissionsCenter.systemAutomationStatus($0, ask: $1) },
                refreshesOnActivation: Bool = false) {
        self.automationProbe = automationProbe
        refresh()
        if refreshesOnActivation {
            activationObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }                     // queue: .main
            }
        }
    }

    /// The last known status. Automation: the cached answer, `.unknown` until the first one lands (asking for it
    /// starts the query off the main actor; never a synchronous Apple Events query). Other kinds are queried if
    /// they were never asked for.
    public func status(_ kind: PermissionKind) -> PermissionStatus {
        if case .automation = kind { return knownStatus(kind) ?? .unknown }
        return statuses[kind] ?? query(kind)
    }

    /// The last known status, or nil while an app's first Automation answer is still on its way (asking starts it;
    /// views read this to show a spinner instead of a wrong status). Never blocks.
    public func knownStatus(_ kind: PermissionKind) -> PermissionStatus? {
        guard case .automation(let bundleID) = kind else { return status(kind) }
        if let known = statuses[kind] { return known }
        if firstQueries.insert(bundleID).inserted {
            Task { [weak self] in
                await self?.queryAutomation(bundleID)
                self?.firstQueries.remove(bundleID)
            }
        }
        return nil
    }

    /// Asks macOS now (Automation off the main actor; never prompts) and updates the cache: for a caller that must
    /// not act on an answer older than this moment (the media fallback before its scripts).
    public func currentStatus(_ kind: PermissionKind) async -> PermissionStatus {
        guard case .automation(let bundleID) = kind else {
            let answer = query(kind)
            update(kind, to: answer)
            return answer
        }
        return await queryAutomation(bundleID)
    }

    /// Re-query everything (Cranny became active, Settings ▸ Permissions appeared): the cheap kinds at once, the
    /// Automation answers already known off the main actor (they land a moment later).
    public func refresh() {
        for kind in [PermissionKind.accessibility, .calendar, .camera, .bluetooth, .systemAudioRecording] {
            update(kind, to: query(kind))
        }
        for case .automation(let bundleID) in statuses.keys {
            Task { [weak self] in await self?.queryAutomation(bundleID) }
        }
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
            let answer = await automationProbe(bundleID, true)           // off the main actor: it blocks while asking
            _ = nextAutomationGeneration(bundleID)                       // the person's answer: queries begun before
            update(kind, to: answer)                                     // it (during the prompt) are dropped
            return answer
        }
        let s = query(kind)
        update(kind, to: s)
        return s
    }

    /// Opens the permission's page of Privacy & Security in System Settings.
    public func openSystemSettings(_ kind: PermissionKind) {
        if let url = kind.settingsURL { NSWorkspace.shared.open(url) }
    }

    /// For kinds without a query API, or an answer a feature observed (tap delivered audio → granted; an Apple Event
    /// refused with −1743 → denied). An Automation query still running is superseded.
    public func record(_ status: PermissionStatus, for kind: PermissionKind) {
        if case .automation(let bundleID) = kind { _ = nextAutomationGeneration(bundleID) }
        recorded[kind] = status
        update(kind, to: status)
    }

    // MARK: Automation cache

    /// Asks `automationProbe` (never prompts) and stores the answer unless a newer query or answer came meanwhile.
    @discardableResult
    private func queryAutomation(_ bundleID: String) async -> PermissionStatus {
        let generation = nextAutomationGeneration(bundleID)
        let answer = await automationProbe(bundleID, false)
        if automationGeneration[bundleID] == generation { update(.automation(bundleID: bundleID), to: answer) }
        return answer
    }

    private func nextAutomationGeneration(_ bundleID: String) -> Int {
        let next = (automationGeneration[bundleID] ?? 0) + 1
        automationGeneration[bundleID] = next
        return next
    }

    /// Writes only a change, so observers (rows reading `statuses`) are not invalidated by every refresh.
    private func update(_ kind: PermissionKind, to status: PermissionStatus) {
        if statuses[kind] != status { statuses[kind] = status }
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
        case .automation:
            return statuses[kind] ?? .unknown         // never queried synchronously: see `queryAutomation`
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

    /// macOS's Automation answer for `bundleID` (`AEDeterminePermissionToAutomateTarget`), off the main actor. It
    /// sends nothing to the app; with `ask` it shows the system prompt and blocks until it is answered (never on the
    /// main thread). `.unknown` while the app is not running (procNotFound).
    @concurrent public nonisolated static func systemAutomationStatus(_ bundleID: String, ask: Bool) async -> PermissionStatus {
        let target = NSAppleEventDescriptor(bundleIdentifier: bundleID)
        guard let desc = target.aeDesc else { return .unknown }
        return map(AEDeterminePermissionToAutomateTarget(desc, typeWildCard, typeWildCard, ask))
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
