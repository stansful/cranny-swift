// CrannyMirror/Model/MirrorPresentation.swift — what the widget shows for a state, as a pure value (unit-tested).
// DESIGN.md §7.4 (off / on) and §6.8 (empty · needs permission · loading · error).
import CrannyCore
import Foundation

nonisolated struct MirrorPresentation: Equatable, Sendable {
    nonisolated enum Glyph: Equatable, Sendable {
        /// `web.camera` in the secondary label colour.
        case camera
        /// Starting: nothing new for 300 ms, then a quiet 2.5-pt ring (DESIGN.md §6.8 "loading").
        case loading
        /// `web.camera` in `danger`, always next to a line of text (never colour alone, §16).
        case problem
    }

    /// What a click does. nil = the card is not a button in this state.
    nonisolated enum Action: Equatable, Sendable { case turnOn, turnOff, openSettings }

    var glyph: Glyph = .camera
    /// The caption under the glyph; empty while the feed shows.
    var message: String
    /// A second, quieter line (why the camera is unavailable).
    var detail: String?
    /// The chip under the message, a visual cue for the card's click (the whole card is the button).
    var actionTitle: String?
    var action: Action?
    var showsFeed = false
    /// VoiceOver: "Camera preview, on".
    var isOn = false

    var accessibilityValue: String {
        if isOn { return MirrorCopy.on }
        // A state that explains itself (no camera, lid closed) says so instead of a bare "Off".
        return message == MirrorCopy.previewCamera ? MirrorCopy.off : [message, detail].compactMap { $0 }.joined(separator: ", ")
    }

    var accessibilityHint: String? {
        switch action {
        case .turnOn: MirrorCopy.turnOnHint
        case .turnOff: MirrorCopy.turnOffHint
        case .openSettings: MirrorCopy.openSettingsHint
        case nil: nil
        }
    }

    /// `isLive` is false on Settings/onboarding stages, in `#Preview`s and while the layout is being edited:
    /// those always show the resting "Preview camera" card and never react to clicks.
    static func make(phase: MirrorPhase, authorization: PermissionStatus, camera: CameraDevice?,
                     devicesLoaded: Bool, isLive: Bool) -> MirrorPresentation {
        guard isLive else { return MirrorPresentation(message: MirrorCopy.previewCamera) }
        switch phase {
        case .running:
            return MirrorPresentation(message: "", action: .turnOff, showsFeed: true, isOn: true)
        case .starting:
            return MirrorPresentation(glyph: .loading, message: MirrorCopy.previewCamera)
        case .requestingAccess:
            return MirrorPresentation(message: MirrorCopy.waitingForAccess)
        case .problem(let error):
            return problem(error, camera: camera)
        case .off:
            switch authorization {
            case .denied: return problem(.notAuthorized, camera: camera)
            case .restricted: return MirrorPresentation(message: MirrorCopy.accessRestricted)
            case .granted, .notDetermined, .unknown: break
            }
            if devicesLoaded, camera == nil { return problem(.noCamera, camera: nil) }
            if let camera, camera.isSuspended { return problem(.suspended, camera: camera) }
            return MirrorPresentation(message: MirrorCopy.previewCamera, action: .turnOn)
        }
    }

    private static func problem(_ error: MirrorError, camera: CameraDevice?) -> MirrorPresentation {
        switch error {
        case .noCamera:
            MirrorPresentation(message: MirrorCopy.noCamera)
        case .suspended:
            // Only the built-in camera is suspended by the lid; a USB camera with a shut privacy cover is not.
            MirrorPresentation(message: MirrorCopy.unavailable, detail: camera?.kind == .builtIn ? MirrorCopy.lidClosed : nil)
        case .notAuthorized:
            MirrorPresentation(message: MirrorCopy.accessOff, actionTitle: MirrorCopy.allowCamera, action: .openSettings)
        case .disconnected, .sessionFailed:
            MirrorPresentation(glyph: .problem, message: MirrorCopy.message(for: error),
                               actionTitle: MirrorCopy.tryAgain, action: .turnOn)
        }
    }
}
