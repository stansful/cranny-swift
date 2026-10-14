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
    /// Calls `onChange` whenever the list may have changed (hot-plug, preferred camera, a camera suspended or
    /// resumed, lid, wake).
    func startWatching(_ onChange: @escaping @MainActor () -> Void)
    func stopWatching()
}

/// AVFoundation discovery: built-in, USB (`.external`, macOS 14) and Continuity cameras (`.continuityCamera`,
/// reported as such because Info.plist sets `NSCameraUseContinuityCameraDeviceType`).
@MainActor final class AVCameraDiscovery: CameraDiscovering {
    private var observers: [(NotificationCenter, any NSObjectProtocol)] = []
    private var preferredObserver: PreferredCameraObserver?
    /// KVO of every listed camera's `isSuspended` (R3 §5: "KVO it"): the lid or a privacy shutter changes it
    /// without any notification. Replaced by each snapshot while watching.
    private var suspensionObservers: SuspensionObservers?
    private var onChange: (@MainActor () -> Void)?

    func snapshot() async -> CameraSnapshot {
        // `[weak self]`: the observers live in `self`; a main-actor class is Sendable, so the hop is safe.
        let notify: (@Sendable () -> Void)? = onChange == nil ? nil : { @Sendable [weak self] () -> Void in
            Task { @MainActor in self?.onChange?() }
        }
        let (snapshot, suspension) = await Self.enumerate(watchingSuspension: notify)
        // Snapshots never overlap (CameraCatalog runs one at a time); stopWatching may have run meanwhile.
        suspensionObservers?.invalidate()
        if onChange != nil { suspensionObservers = suspension } else { suspension?.invalidate(); suspensionObservers = nil }
        return snapshot
    }

    @concurrent private static func enumerate(watchingSuspension notify: (@Sendable () -> Void)?) async -> (CameraSnapshot, SuspensionObservers?) {
        let types: [AVCaptureDevice.DeviceType] = [.builtInWideAngleCamera, .external, .continuityCamera]
        let session = AVCaptureDevice.DiscoverySession(deviceTypes: types, mediaType: .video, position: .unspecified)
        let devices = session.devices
        // `isSuspended` is documented as key-value observable; observing it never prompts (no input is created).
        let suspension = notify.map { notify in
            SuspensionObservers(devices.map { device in
                device.observe(\.isSuspended, options: [.new]) { @Sendable _, _ in notify() }
            })
        }
        let snapshot = CameraSnapshot(devices: devices.map(CameraDevice.init(device:)),
                                      systemPreferredID: AVCaptureDevice.systemPreferredCamera?.uniqueID)
        return (snapshot, suspension)
    }

    func startWatching(_ onChange: @escaping @MainActor () -> Void) {
        guard observers.isEmpty else { return }
        self.onChange = onChange
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
        suspensionObservers?.invalidate()
        suspensionObservers = nil
        onChange = nil
    }
}

/// The `isSuspended` observations of one snapshot. Created on the enumeration's executor and handed to the main
/// actor: the array is immutable, and `NSKeyValueObservation.invalidate()` may be called from any thread and more
/// than once (deinit calls it too) — hence `@unchecked Sendable`.
private nonisolated final class SuspensionObservers: @unchecked Sendable {
    private let observations: [NSKeyValueObservation]
    init(_ observations: [NSKeyValueObservation]) { self.observations = observations }
    func invalidate() { observations.forEach { $0.invalidate() } }
    deinit { invalidate() }
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
    // `onChange` and `target` are immutable; `isObserving` is only touched by init, `invalidate` and deinit, which
    // all run on the main actor (the owner, AVCameraDiscovery, is main-actor) — hence `@unchecked Sendable`.
    private let onChange: @Sendable () -> Void
    private let target: AnyObject = AVCaptureDevice.self
    private var isObserving = true
    private static let keyPath = "systemPreferredCamera"

    init(onChange: @escaping @Sendable () -> Void) {
        self.onChange = onChange
        super.init()
        target.addObserver(self, forKeyPath: Self.keyPath, options: [.new], context: nil)
    }

    /// Unregisters (once). A registered observer must never outlive itself, so deinit calls it too.
    func invalidate() {
        guard isObserving else { return }
        isObserving = false
        target.removeObserver(self, forKeyPath: Self.keyPath)
    }

    deinit { invalidate() }

    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?,
                               context: UnsafeMutableRawPointer?) {
        onChange()
    }
}
