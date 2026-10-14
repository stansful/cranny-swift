// Test doubles for the Mirror: no AVFoundation, no TCC, no hardware.
import CrannyCore
import Foundation
import Observation
@testable import CrannyMirror

/// Records every start and stop; tests send the hardware's answers with `send`.
final class FakeCameraController: CameraControlling {
    var onEvent: (@MainActor (CameraEvent) -> Void)?
    private(set) var feed: CameraFeed?
    private(set) var starts: [String] = []
    private(set) var stops = 0

    /// The camera is on (last call was a start).
    private(set) var isOn = false

    func start(deviceID: String) { starts.append(deviceID); feed = .sample; isOn = true }
    func stop() { stops += 1; feed = nil; isOn = false }
    func send(_ event: CameraEvent) { onEvent?(event) }
}

/// A camera list the test changes; `change` behaves like a hot-plug notification.
final class FakeDiscovery: CameraDiscovering {
    var snapshotValue: CameraSnapshot
    private(set) var isWatching = false
    private(set) var enumerations = 0
    private var onChange: (@MainActor () -> Void)?

    init(_ snapshot: CameraSnapshot) { snapshotValue = snapshot }

    func snapshot() async -> CameraSnapshot { enumerations += 1; return snapshotValue }
    func startWatching(_ onChange: @escaping @MainActor () -> Void) { isWatching = true; self.onChange = onChange }
    func stopWatching() { isWatching = false; onChange = nil }

    func change(_ snapshot: CameraSnapshot) {
        snapshotValue = snapshot
        onChange?()
    }
}

/// Camera permission whose prompt stays up until the test answers it.
@Observable final class FakeAuthorization: CameraAuthorizing {
    var status: PermissionStatus
    private(set) var requests = 0
    private(set) var forcedRefreshes = 0
    private(set) var settingsOpened = 0
    @ObservationIgnored private var pending: CheckedContinuation<PermissionStatus, Never>?

    init(_ status: PermissionStatus) { self.status = status }

    var isPromptShowing: Bool { pending != nil }

    func refresh(force: Bool) { if force { forcedRefreshes += 1 } }

    func request() async -> PermissionStatus {
        requests += 1
        return await withCheckedContinuation { pending = $0 }
    }

    /// The user answers the system prompt.
    func answer(_ answer: PermissionStatus) {
        status = answer
        pending?.resume(returning: answer)
        pending = nil
    }

    func openSystemSettings() { settingsOpened += 1 }
}

/// A model on fakes, with the preview doubles of Core for the notch and the environment.
@MainActor struct MirrorHarness {
    let settings: SettingsStore
    let notch = PreviewNotchControl()
    let environment = PreviewSystemEnvironment()
    let controller = FakeCameraController()
    let discovery: FakeDiscovery
    let authorization: FakeAuthorization
    let model: MirrorModel

    init(_ status: PermissionStatus = .granted, cameras: CameraSnapshot = Cameras.two, activated: Bool = true) {
        settings = CrannyServices.preview().settings
        discovery = FakeDiscovery(cameras)
        authorization = FakeAuthorization(status)
        model = MirrorModel(settings: settings, notch: notch, environment: environment,
                            catalog: CameraCatalog(discovery: discovery), controller: controller,
                            authorization: authorization)
        if activated { model.activate() }
    }

    /// The context of the widget in the real open panel.
    static let live = WidgetContext(cells: 2, contentSize: CGSize(width: 120, height: 120))

    /// A live widget appears in the open panel and the camera list has loaded.
    @discardableResult func show(_ id: UUID = UUID()) async -> UUID {
        model.viewAppeared(id, context: Self.live)
        await model.catalog.ensureLoaded()
        return id
    }

    /// Visible, clicked once, and the hardware confirms: the Mirror is running.
    @discardableResult func run() async -> UUID {
        let id = await show()
        await model.tap()
        if let deviceID = controller.starts.last { controller.send(.started(deviceID: deviceID)) }
        return id
    }

    var holds: [String] { notch.calls.filter { $0.hasPrefix("hold(") } }
}

enum Cameras {
    static let builtIn = CameraDevice(id: "cam.builtIn", name: "FaceTime HD Camera", kind: .builtIn)
    static let iPhone = CameraDevice(id: "cam.iphone", name: "Desk iPhone", kind: .continuity)
    static let usb = CameraDevice(id: "cam.usb", name: "USB Camera", kind: .external)
    static let deskView = CameraDevice(id: "cam.desk", name: "Desk View Camera", kind: .deskView)

    static let two = CameraSnapshot(devices: [builtIn, iPhone], systemPreferredID: builtIn.id)
    static let builtInOnly = CameraSnapshot(devices: [builtIn], systemPreferredID: builtIn.id)
    static let lidClosed = CameraSnapshot(devices: [CameraDevice(id: builtIn.id, name: builtIn.name, kind: .builtIn, isSuspended: true)],
                                          systemPreferredID: nil)
    static let none = CameraSnapshot(devices: [], systemPreferredID: nil)
}

/// Polls `condition` on the main actor until it holds or `timeout` passes (observation callbacks are async).
@MainActor func eventually(within timeout: Duration = .seconds(1), _ condition: () -> Bool) async -> Bool {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while clock.now < deadline {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(5))
    }
    return condition()
}
