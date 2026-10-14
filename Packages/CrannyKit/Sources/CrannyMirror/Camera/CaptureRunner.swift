// CrannyMirror/Camera/CaptureRunner.swift — the blocking AVCaptureSession work.
//
// THREADING: every method runs on `CameraController`'s private serial queue and nowhere else (that queue is the
// only caller). `startRunning`/`stopRunning` block for tens to hundreds of milliseconds, which is why they must
// never run on the main thread (R3 §5). The runner has no other state than `input`, which only that queue
// touches — hence `@unchecked Sendable`.
import AVFoundation
import CrannyCore
import Foundation
import os

nonisolated private let log = Log.logger(.mirror)

nonisolated final class CaptureRunner: @unchecked Sendable {
    let handle = CaptureSessionHandle()
    private var input: AVCaptureDeviceInput?

    /// Presets in order of preference. The preview is at most 3 cells (≈ 184 × 120 pt, 368 × 240 px on Retina):
    /// VGA fills it sharply after aspect-fill, at a fraction of the cost of the camera's full resolution.
    private static let presets: [AVCaptureSession.Preset] = [.vga640x480, .medium, .high]

    /// Configures the session for `deviceID` and starts it. Returns nil on success.
    func start(deviceID: String) -> MirrorError? {
        let session = handle.session
        guard let device = AVCaptureDevice(uniqueID: deviceID), device.isConnected else { return .disconnected }
        guard !device.isSuspended else { return .suspended }

        session.beginConfiguration()
        if let input { session.removeInput(input); self.input = nil }
        let newInput: AVCaptureDeviceInput
        do {
            newInput = try AVCaptureDeviceInput(device: device)
        } catch {
            session.commitConfiguration()
            let code = (error as NSError).code
            log.error("camera input failed: \(code, privacy: .public)")
            return code == AVError.Code.applicationIsNotAuthorizedToUseDevice.rawValue ? .notAuthorized : .sessionFailed
        }
        guard session.canAddInput(newInput) else {
            session.commitConfiguration()
            log.error("session refused the camera input")
            return .sessionFailed
        }
        session.addInput(newInput)
        input = newInput
        if let preset = Self.presets.first(where: session.canSetSessionPreset) { session.sessionPreset = preset }
        session.commitConfiguration()

        session.startRunning()
        guard session.isRunning else {
            log.error("session did not start")
            stop()
            return .sessionFailed
        }
        return nil
    }

    /// Stops the session and detaches the camera, so the system's green indicator goes out.
    func stop() {
        let session = handle.session
        if session.isRunning { session.stopRunning() }
        guard let input else { return }
        session.beginConfiguration()
        session.removeInput(input)
        session.commitConfiguration()
        self.input = nil
    }
}
