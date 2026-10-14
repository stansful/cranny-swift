// CrannyMirror/Preview/MirrorSamples.swift — hardware-free stand-ins for #Previews and the Debug visual-QA
// scenarios (`--qa-mirror`, MirrorQA.swift). They never touch AVFoundation or TCC. The live module uses
// `CameraController`, `AVCameraDiscovery` and `PermissionsCenterAuthorization`.
import CrannyCore
import Foundation
import Observation

/// "Starts" after a short, realistic delay and shows the drawn sample feed (or fails, for the error state).
final class SampleCameraController: CameraControlling {
    var onEvent: (@MainActor (CameraEvent) -> Void)?
    private(set) var feed: CameraFeed?
    private let startDelay: Duration
    private let failure: MirrorError?
    private var pending: Task<Void, Never>?

    init(startDelay: Duration = .milliseconds(450), failure: MirrorError? = nil) {
        self.startDelay = startDelay; self.failure = failure
    }

    func start(deviceID: String) {
        pending?.cancel()
        feed = .sample
        pending = Task { [weak self, startDelay, failure] in
            try? await Task.sleep(for: startDelay)
            guard let self, !Task.isCancelled else { return }
            if let failure { feed = nil; onEvent?(.failed(failure)) } else { onEvent?(.started(deviceID: deviceID)) }
        }
    }

    func stop() {
        pending?.cancel()
        feed = nil
    }
}

/// A fixed camera list.
final class SampleCameraDiscovery: CameraDiscovering {
    var snapshotValue: CameraSnapshot

    init(_ snapshot: CameraSnapshot = SampleCameraDiscovery.twoCameras) { snapshotValue = snapshot }

    func snapshot() async -> CameraSnapshot { snapshotValue }
    func startWatching(_ onChange: @escaping @MainActor () -> Void) {}
    func stopWatching() {}

    /// A built-in camera and a Continuity Camera (fictional names, never a real person's device).
    static let twoCameras = CameraSnapshot(devices: [
        CameraDevice(id: "sample.builtIn", name: "FaceTime HD Camera", kind: .builtIn),
        CameraDevice(id: "sample.continuity", name: "Studio iPhone Camera", kind: .continuity),
    ], systemPreferredID: "sample.builtIn")
    /// The built-in camera with the lid closed (clamshell mode).
    static let lidClosed = CameraSnapshot(devices: [
        CameraDevice(id: "sample.builtIn", name: "FaceTime HD Camera", kind: .builtIn, isSuspended: true),
    ], systemPreferredID: nil)
    static let none = CameraSnapshot(devices: [], systemPreferredID: nil)
}

/// A fixed permission answer.
@Observable final class SampleCameraAuthorization: CameraAuthorizing {
    var status: PermissionStatus
    init(_ status: PermissionStatus = .granted) { self.status = status }
    func refresh(force: Bool) {}
    func request() async -> PermissionStatus { status }
    func openSystemSettings() {}
}

extension MirrorModel {
    /// A model with sample parts in `phase`, for #Previews. Never starts hardware.
    static func preview(phase: MirrorPhase = .off, authorization: PermissionStatus = .granted,
                        cameras: CameraSnapshot = SampleCameraDiscovery.twoCameras) -> MirrorModel {
        let services = CrannyServices.preview()
        let model = MirrorModel(settings: services.settings, notch: services.notch, environment: services.environment,
                                catalog: CameraCatalog(discovery: SampleCameraDiscovery(cameras)),
                                controller: SampleCameraController(), authorization: SampleCameraAuthorization(authorization))
        model.catalog.activate()
        model.showPreviewState(phase)
        return model
    }
}
