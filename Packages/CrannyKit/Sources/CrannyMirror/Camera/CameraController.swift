// CrannyMirror/Camera/CameraController.swift — the live camera: one AVCaptureSession, started and stopped on a
// private serial queue (`CaptureRunner`), watched for runtime errors, unplugging and suspension.
//
// THREADING: this façade is main-actor; all session work is dispatched to `queue`. Results and notifications
// come back to the main actor, tagged with the generation they belong to so a stop or restart drops stale ones.
// Nothing here runs until the model asks for a start, which only a click on a visible widget can cause.
import AVFoundation
import CrannyCore
import Foundation
import os

/// Nonisolated: the notification readers below may run off the main actor (`Logger` is Sendable).
nonisolated private let log = Log.logger(.mirror)

final class CameraController: CameraControlling {
    var onEvent: (@MainActor (CameraEvent) -> Void)?
    private(set) var feed: CameraFeed?

    private let queue = DispatchQueue(label: "app.cranny.mirror.capture", qos: .userInitiated)
    /// Created on the first start, never at registration (no capture objects before the user asks).
    private var runner: CaptureRunner?
    private var generation = 0
    private var observers: [any NSObjectProtocol] = []
    private var suspension: NSKeyValueObservation?

    func start(deviceID: String) {
        generation += 1
        let current = generation
        removeObservers()
        let runner = self.runner ?? CaptureRunner()
        self.runner = runner
        feed = .session(runner.handle)
        log.info("starting camera")
        queue.async { [weak self] in
            let error = runner.start(deviceID: deviceID)
            Task { @MainActor in self?.finishStart(deviceID: deviceID, error: error, generation: current) }
        }
    }

    func stop() {
        generation += 1
        removeObservers()
        feed = nil
        guard let runner else { return }
        log.info("stopping camera")
        queue.async { runner.stop() }
    }

    // MARK: Results

    private func finishStart(deviceID: String, error: MirrorError?, generation started: Int) {
        guard started == generation else { return }                       // stopped or restarted meanwhile
        if let error {
            feed = nil
            onEvent?(.failed(error))
            return
        }
        watch(deviceID: deviceID, generation: started)
        onEvent?(.started(deviceID: deviceID))
    }

    /// Runtime errors, the session stopping on its own, the camera unplugged or suspended (lid closed).
    private func watch(deviceID: String, generation watched: Int) {
        guard let session = runner?.handle.session else { return }
        let center = NotificationCenter.default
        /// `event` reads the (non-Sendable) notification where it is delivered and returns a Sendable value;
        /// `queue: .main` delivers on the main thread, hence `assumeIsolated` (ARCHITECTURE.md §9.1 rule 4).
        func observe(_ name: Notification.Name, object: AnyObject?, _ event: @escaping @Sendable (Notification) -> CameraEvent?) {
            observers.append(center.addObserver(forName: name, object: object, queue: .main) { [weak self] note in
                guard let event = event(note) else { return }
                MainActor.assumeIsolated {
                    guard let self, self.generation == watched else { return }
                    self.report(event)
                }
            })
        }
        observe(AVCaptureSession.runtimeErrorNotification, object: session) { note in
            let code = (note.userInfo?[AVCaptureSessionErrorKey] as? NSError)?.code ?? 0
            log.error("camera runtime error: \(code, privacy: .public)")
            return .failed(.sessionFailed)
        }
        observe(AVCaptureSession.didStopRunningNotification, object: session) { _ in .stoppedBySystem }
        observe(AVCaptureDevice.wasDisconnectedNotification, object: nil) { note in
            (note.object as? AVCaptureDevice)?.uniqueID == deviceID ? .failed(.disconnected) : nil
        }
        // KVO may fire on any thread: hop to the main actor before touching state.
        suspension = AVCaptureDevice(uniqueID: deviceID)?.observe(\.isSuspended, options: [.new]) { @Sendable [weak self] device, _ in
            guard device.isSuspended else { return }
            Task { @MainActor in
                guard let self, self.generation == watched else { return }
                self.report(.failed(.suspended))
            }
        }
    }

    /// A running camera hit a problem: forget the session's observers; the model answers with `stop()`.
    private func report(_ event: CameraEvent) {
        removeObservers()
        onEvent?(event)
    }

    private func removeObservers() {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers.removeAll()
        suspension?.invalidate()
        suspension = nil
    }
}
