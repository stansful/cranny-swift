// CrannyMirror/Camera/CameraControlling.swift — the seam between the Mirror's state machine and the camera
// hardware. Live: `CameraController` (AVCaptureSession on a private queue). Tests: a recording fake. Previews
// and visual QA: `SampleCameraController` (no hardware at all).
import AVFoundation
import Foundation

/// Why the camera is not showing. Every case has a calm, localized one-liner (DESIGN.md §17); raw `NSError`
/// text never reaches the UI (ARCHITECTURE.md §9.3).
nonisolated enum MirrorError: Error, LocalizedError, Equatable, Sendable {
    /// No camera is connected.
    case noCamera
    /// The camera is suspended: the lid is closed (built-in) or its privacy shutter is shut.
    case suspended
    /// The camera went away while it was starting or running (USB unplugged, iPhone walked off).
    case disconnected
    /// Camera access was revoked after the last check.
    case notAuthorized
    /// The capture session could not start or stopped with a runtime error.
    case sessionFailed

    var errorDescription: String? { MirrorCopy.message(for: self) }
}

/// What the hardware reports back to the model (always on the main actor).
nonisolated enum CameraEvent: Equatable, Sendable {
    /// The session runs with this camera; frames follow within a moment.
    case started(deviceID: String)
    /// Starting failed, or a running camera hit a problem.
    case failed(MirrorError)
    /// The system stopped the session on its own (sleep, another app took the camera exclusively).
    case stoppedBySystem
}

/// The capture session behind a live feed. AVCaptureSession is not Sendable: after creation it is configured,
/// started and stopped only on `CameraController`'s serial queue; the main actor only hands it to an
/// `AVCaptureVideoPreviewLayer` (Apple's documented pattern), which is safe while the queue works on it.
nonisolated final class CaptureSessionHandle: @unchecked Sendable {
    let session = AVCaptureSession()
}

/// What the preview draws while the camera runs.
enum CameraFeed {
    /// Real frames from an `AVCaptureSession` (CameraPreviewView).
    case session(CaptureSessionHandle)
    /// A drawn stand-in for previews and visual QA (SampleFeedView). Never used by the live module.
    case sample
}

/// The camera hardware: start one camera, stop it, report what happened. Calls never block the main actor.
@MainActor protocol CameraControlling: AnyObject {
    /// Set once by the model. Events from a start that was superseded by `stop()` or another `start` are dropped.
    var onEvent: (@MainActor (CameraEvent) -> Void)? { get set }
    /// The feed of the current (or last requested) session; nil while stopped.
    var feed: CameraFeed? { get }
    /// Starts `deviceID` (replacing any running camera). Reports `.started` or `.failed` through `onEvent`.
    func start(deviceID: String)
    /// Stops the camera and releases it (the green indicator goes out within a few hundred milliseconds).
    func stop()
}
