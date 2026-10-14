// CrannyCore/CrannyCore.swift
// Module overview: DesignSystem/ (DESIGN.md tokens + components), Contracts/ (module plug-in API),
// Services/ (ports + hub), Settings/, Permissions/, Input/, Platform/.
import Foundation

public extension PermissionKind {
    /// Localized name for Settings ▸ Permissions and onboarding rows.
    var title: String {
        switch self {
        case .accessibility: String(localized: "Accessibility", bundle: .module, comment: "Permission name (System Settings ▸ Privacy)")
        case .calendar: String(localized: "Calendars", bundle: .module, comment: "Permission name")
        case .camera: String(localized: "Camera", bundle: .module, comment: "Permission name")
        case .bluetooth: String(localized: "Bluetooth", bundle: .module, comment: "Permission name")
        case .systemAudioRecording: String(localized: "System Audio Recording", bundle: .module, comment: "Permission name")
        case .automation(let bundleID):
            String(localized: "Automation (\(bundleID))", bundle: .module, comment: "Permission name; argument is an app bundle identifier")
        }
    }
}
