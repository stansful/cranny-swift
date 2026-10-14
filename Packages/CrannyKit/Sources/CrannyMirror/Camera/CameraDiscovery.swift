// CrannyMirror/Camera/CameraDiscovery.swift — where the camera list comes from. AVFoundation in the app; a
// fixed list in tests, previews and visual QA. Enumeration and these observers never prompt for camera access
// (R3 §5: the status stays "not determined"); only creating an input does, and that happens after a click.
import AppKit
import AVFoundation
import CrannyCore
import Foundation

/// One enumeration: the cameras and the system's preferred one.
nonisolated struct CameraSnapshot: Equatable, Sendable {
    var devices: [CameraDevice]
    var systemPreferredID: String?
}

@MainActor protocol CameraDiscovering: AnyObject {
    /// Enumerates the cameras (off the main actor in the live implementation).
    func snapshot() async -> CameraSnapshot
    /// Calls `onChange` whenever the list may have changed (hot-plug, preferred camera, lid, wake).
    func startWatching(_ onChange: @escaping @MainActor () -> Void)
    func stopWatching()
}

/// AVFoundation discovery: built-in, USB (`.external`, macOS 14) and Continuity cameras (`.continuityCamera`,
/// reported as such because Info.plist sets `NSCameraUseContinuityCameraDeviceType`).
@MainActor final class AVCameraDiscovery: CameraDiscovering {
    private var observers: [(NotificationCenter, any NSObjectProtocol)] = []
    private var preferredObserver: PreferredCameraObserver?

    func snapshot() async -> CameraSnapshot { await Self.enumerate() }

    @concurrent private static func enumerate() async -> CameraSnapshot {
        let types: [AVCaptureDevice.DeviceType] = [.builtInWideAngleCamera, .external, .continuityCamera]
        let session = AVCaptureDevice.DiscoverySession(deviceTypes: types, mediaType: .video, position: .unspecified)
        return CameraSnapshot(devices: session.devices.map(CameraDevice.init(device:)),
                              systemPreferredID: AVCaptureDevice.systemPreferredCamera?.uniqueID)
    }

    func startWatching(_ onChange: @escaping @MainActor () -> Void) {
        guard observers.isEmpty else { return }
        let app = NotificationCenter.default, workspace = NSWorkspace.shared.notificationCenter
        let names: [(NotificationCenter, Notification.Name)] = [
            (app, AVCaptureDevice.wasConnectedNotification),
            (app, AVCaptureDevice.wasDisconnectedNotification),
            (app, NSApplication.didChangeScreenParametersNotification),   // lid opened/closed: built-in (un)suspends
            (workspace, NSWorkspace.didWakeNotification),
        ]
        for (center, name) in names {
            // Delivered on the main queue (`queue: .main`), hence `assumeIsolated` (ARCHITECTURE.md §9.1 rule 4).
            let token = center.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { onChange() }
            }
            observers.append((center, token))
        }
        // Apple: "Applications that adopt this API should always key-value observe this property."
        preferredObserver = PreferredCameraObserver { Task { @MainActor in onChange() } }
    }

    func stopWatching() {
        for (center, token) in observers { center.removeObserver(token) }
        observers.removeAll()
        preferredObserver?.invalidate()
        preferredObserver = nil
    }
}

extension CameraDevice {
    /// Reads the device's identity and state (call where the `AVCaptureDevice` lives; it is not Sendable).
    nonisolated init(device: AVCaptureDevice) {
        let kind: Kind = switch device.deviceType {
        case .builtInWideAngleCamera: .builtIn
        case .continuityCamera: .continuity
        case .external: .external
        case .deskViewCamera: .deskView
        default: .other
        }
        self.init(id: device.uniqueID, name: device.localizedName, kind: kind, isSuspended: device.isSuspended)
    }
}

/// Key-value observes the CLASS property `AVCaptureDevice.systemPreferredCamera`. Swift's key-path `observe`
/// works on instances only, so this uses classic KVO. `onChange` may run on any thread (it hops to main).
private nonisolated final class PreferredCameraObserver: NSObject, @unchecked Sendable {
    // Immutable after init; `invalidate` runs once, on the main actor (thread-safety of the two fields).
    private let onChange: @Sendable () -> Void
    private let target: AnyObject = AVCaptureDevice.self
    private static let keyPath = "systemPreferredCamera"

    init(onChange: @escaping @Sendable () -> Void) {
        self.onChange = onChange
        super.init()
        target.addObserver(self, forKeyPath: Self.keyPath, options: [.new], context: nil)
    }

    func invalidate() { target.removeObserver(self, forKeyPath: Self.keyPath) }

    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?,
                               context: UnsafeMutableRawPointer?) {
        onChange()
    }
}
