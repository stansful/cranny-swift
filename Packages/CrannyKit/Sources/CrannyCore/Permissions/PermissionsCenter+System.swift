// CrannyCore/Permissions/PermissionsCenter+System.swift
// What macOS answers when asked about a permission: the class-level TCC queries (never prompt, safe on any thread, so
// a background refresh asks them off the main actor) and the Automation check per app (`AEDeterminePermissionToAutomateTarget`,
// never on the main thread: with `ask` it blocks while the prompt is up).
import ApplicationServices
import AVFoundation
import CoreBluetooth
import CoreServices
import EventKit
import Foundation

extension PermissionsCenter {
    /// macOS's answer for Accessibility, Calendar, Camera or Bluetooth (`.unknown` for the others, which have no
    /// such query). Never prompts; class-level TCC queries that are safe on any thread (a background refresh asks
    /// them off the main actor).
    public nonisolated static func systemStatus(_ kind: PermissionKind) -> PermissionStatus {
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
        case .systemAudioRecording, .automation:
            return .unknown
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
