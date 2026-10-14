// CrannyMirror/MirrorCopy.swift — every user-visible string of the module in one place, so each key has
// exactly one translator comment ("<Surface>: <purpose>", ARCHITECTURE.md §10.0). Voice: calm, plain,
// sentence case (DESIGN.md §17). Russian lives in Resources/Localizable.xcstrings.
import Foundation

nonisolated enum MirrorCopy {
    // MARK: Widget

    /// Widget name (library, VoiceOver container, Live Activities never shows it).
    static var widgetTitle: String { String(localized: "Mirror", bundle: .module, comment: "Mirror: widget name (widget library, VoiceOver container)") }
    static var widgetSummary: String { String(localized: "See yourself before a call", bundle: .module, comment: "Widget library: Mirror description") }

    // MARK: States (DESIGN.md §7.4, §6.8)

    /// The off state: one click starts the camera.
    static var previewCamera: String { String(localized: "Preview camera", bundle: .module, comment: "Mirror widget: off state; a click turns the camera on") }
    static var waitingForAccess: String { String(localized: "Waiting for camera access", bundle: .module, comment: "Mirror widget: the system camera permission prompt is showing") }
    static var accessOff: String { String(localized: "Camera access is off", bundle: .module, comment: "Mirror widget: camera permission was denied") }
    static var accessRestricted: String { String(localized: "Camera access is restricted", bundle: .module, comment: "Mirror widget: camera blocked by a device management profile or Screen Time") }
    /// The chip under `accessOff` names the outcome, not the destination: "Settings" alone reads as Cranny's own
    /// Settings (the panel's gear, ⌘,), and "Open System Settings" does not fit one line of a 2-cell card
    /// (`MirrorResourceTests.chipTitlesFitTheNarrowestCard`). The VoiceOver hint names System Settings.
    static var allowCamera: String {
        String(localized: "Allow…", bundle: .module,
               comment: "Mirror widget: chip under “Camera access is off”; a click opens System Settings ▸ Privacy & Security ▸ Camera to allow the camera (a word or two: one line in a 2-cell card)")
    }
    static var noCamera: String { String(localized: "No camera connected", bundle: .module, comment: "Mirror widget: no camera is connected") }
    static var unavailable: String { String(localized: "Camera unavailable", bundle: .module, comment: "Mirror widget: the camera is suspended (first line)") }
    static var lidClosed: String { String(localized: "The lid is closed", bundle: .module, comment: "Mirror widget: why the built-in camera is suspended (second line)") }
    static var disconnected: String { String(localized: "Camera disconnected", bundle: .module, comment: "Mirror widget: the camera in use was unplugged or went out of range") }
    static var stopped: String { String(localized: "The camera stopped", bundle: .module, comment: "Mirror widget: the capture session failed") }
    static var tryAgain: String { String(localized: "Try again", bundle: .module, comment: "Mirror widget: chip that starts the camera again after a problem") }

    /// The one-liner for a problem (also `MirrorError.errorDescription`).
    static func message(for error: MirrorError) -> String {
        switch error {
        case .noCamera: noCamera
        case .suspended: unavailable
        case .disconnected: disconnected
        case .notAuthorized: accessOff
        case .sessionFailed: stopped
        }
    }

    // MARK: VoiceOver

    static var previewLabel: String { String(localized: "Camera preview", bundle: .module, comment: "Mirror widget: VoiceOver label of the card (read as “Camera preview, on”)") }
    static var on: String { String(localized: "On", bundle: .module, comment: "Mirror widget: VoiceOver value while the camera is on") }
    static var off: String { String(localized: "Off", bundle: .module, comment: "Mirror widget: VoiceOver value while the camera is off") }
    static var turnOnHint: String { String(localized: "Turns the camera on", bundle: .module, comment: "Mirror widget: VoiceOver hint while the camera is off") }
    static var turnOffHint: String { String(localized: "Turns the camera off", bundle: .module, comment: "Mirror widget: VoiceOver hint while the camera is on") }
    static var openSettingsHint: String { String(localized: "Opens System Settings", bundle: .module, comment: "Mirror widget: VoiceOver hint when camera access is off") }

    // MARK: Toolbar and options

    static var mirrorImage: String { String(localized: "Mirror the image", bundle: .module, comment: "Mirror widget: flip button (VoiceOver) and options toggle") }
    static var flipHelp: String { String(localized: "Flip horizontally", bundle: .module, comment: "Mirror widget: tooltip of the flip button") }
    static var camera: String { String(localized: "Camera", bundle: .module, comment: "Mirror widget: camera menu (tooltip, VoiceOver) and options picker label") }
    static var automatic: String { String(localized: "Automatic", bundle: .module, comment: "Mirror widget: camera menu item that follows the system's preferred camera") }
    static func unavailableCamera(_ name: String) -> String {
        String(localized: "\(name) (unavailable)", bundle: .module, comment: "Mirror widget: camera menu item for a suspended camera; argument is the camera name")
    }
    static var optionsFootnote: String {
        String(localized: "The camera turns on only when you click the widget and turns off when Cranny closes.", bundle: .module,
               comment: "Mirror options: footnote under the camera and mirroring rows")
    }

    // MARK: Permissions

    static var permissionReason: String {
        String(localized: "Show your camera in the Mirror widget. Cranny never records or saves video.", bundle: .module,
               comment: "Permissions pane and onboarding: why Mirror needs the camera")
    }
}

/// SF Symbols of the module (DESIGN.md §14.1 "Mirror"; `video*` symbols are FaceTime-only and never used).
nonisolated enum MirrorSymbol {
    /// The widget glyph and every placeholder state (macOS 13+). Errors tint it `danger` and always add text.
    static let camera = "web.camera"
    /// The camera menu in the hover toolbar.
    static let cameraMenu = "camera.fill"
    /// The flip button in the hover toolbar.
    static let flip = "flip.horizontal"

    static let all = [camera, cameraMenu, flip]
}
