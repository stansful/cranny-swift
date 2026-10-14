// CrannyMirror/Model/MirrorMachine.swift — the Mirror's state machine as a pure reducer (unit-tested without
// hardware). `MirrorModel` feeds it events and executes the effects it returns.
//
// Privacy contract (DESIGN.md §7.4, ARCHITECTURE.md §7.5): the camera never starts by itself — only a tap
// starts it, and only while the widget is visible in the open panel; `halt` (close, page change, lock, sleep,
// disappear, layout editing) always returns to `.off`, and a later tap is needed to start again.
import CrannyCore

/// Where the Mirror is.
nonisolated enum MirrorPhase: Equatable, Sendable {
    /// Not running. The widget shows "Preview camera" (or why it cannot run).
    case off
    /// The system's camera prompt is up; the panel is held open meanwhile (ARCHITECTURE.md §4.5).
    case requestingAccess
    /// The session is starting with this camera.
    case starting(deviceID: String)
    /// Frames are showing.
    case running(deviceID: String)
    /// A tap could not start the camera, or a running camera stopped with a problem.
    case problem(MirrorError)

    /// The camera hardware is (or is about to be) in use.
    var usesCamera: Bool {
        switch self {
        case .starting, .running: true
        case .off, .requestingAccess, .problem: false
        }
    }

    /// For logs: the state without the camera's unique ID (a hardware identifier).
    var logName: String {
        switch self {
        case .off: "off"
        case .requestingAccess: "requestingAccess"
        case .starting: "starting"
        case .running: "running"
        case .problem(let error): "problem(\(error))"
        }
    }
}

/// What happens to the Mirror.
nonisolated enum MirrorEvent: Equatable, Sendable {
    /// The user clicked the card (or used its VoiceOver/keyboard action).
    case tap
    /// The system camera prompt was answered.
    case accessResult(PermissionStatus)
    /// The hardware reported back.
    case camera(CameraEvent)
    /// Cameras were plugged or unplugged, one was suspended, the preferred camera or the user's choice changed.
    case devicesChanged
    /// The widget may not show the camera any more (panel closed, page changed, lock, sleep, hidden, editing).
    case halt
}

/// What the model must do.
nonisolated enum MirrorEffect: Equatable, Sendable {
    case requestAccess
    case start(deviceID: String)
    case stop
    /// Keep the panel open while the permission prompt is up ("mirror.permission").
    case holdOpen(Bool)
    case openSystemSettings
}

/// The facts the reducer reads, sampled by the model at each event.
nonisolated struct MirrorInputs: Equatable, Sendable {
    /// Camera permission (never prompts to read).
    var authorization: PermissionStatus
    /// The camera to use: the user's choice, else the system's preferred camera (`CameraCatalog.resolve`).
    var camera: CameraDevice?
    /// Every connected camera (`CameraDevice.id`), to tell "the camera in use went away" from "another was chosen".
    var connectedIDs: Set<String>
    /// The widget is on screen in the open panel, the screen is unlocked and the displays are awake.
    var isEligible: Bool

    init(authorization: PermissionStatus, camera: CameraDevice?, connectedIDs: Set<String>? = nil, isEligible: Bool) {
        self.authorization = authorization; self.camera = camera
        self.connectedIDs = connectedIDs ?? Set(camera.map { [$0.id] } ?? [])
        self.isEligible = isEligible
    }
}

nonisolated enum MirrorMachine {
    static func reduce(_ phase: MirrorPhase, _ event: MirrorEvent, _ inputs: MirrorInputs) -> (MirrorPhase, [MirrorEffect]) {
        switch event {
        case .tap:
            return tap(phase, inputs)

        case .accessResult(let status):
            guard phase == .requestingAccess else { return (phase, []) }      // halted meanwhile: hold already released
            guard status == .granted, inputs.isEligible else { return (.off, [.holdOpen(false)]) }
            let (next, effects) = start(inputs)
            return (next, [.holdOpen(false)] + effects)

        case .camera(let cameraEvent):
            return camera(phase, cameraEvent)

        case .devicesChanged:
            return devicesChanged(phase, inputs)

        case .halt:
            switch phase {
            case .off: return (.off, [])
            case .requestingAccess: return (.off, [.holdOpen(false)])
            case .starting, .running: return (.off, [.stop])
            case .problem: return (.off, [])
            }
        }
    }

    // MARK: Events

    private static func tap(_ phase: MirrorPhase, _ inputs: MirrorInputs) -> (MirrorPhase, [MirrorEffect]) {
        guard inputs.isEligible else { return (phase, []) }
        switch phase {
        case .running:
            return (.off, [.stop])                                             // the card is a toggle
        case .starting, .requestingAccess:
            return (phase, [])
        case .off, .problem:
            switch inputs.authorization {
            case .granted: return start(inputs)
            case .notDetermined, .unknown: return (.requestingAccess, [.holdOpen(true), .requestAccess])
            case .denied: return (.off, [.openSystemSettings])                 // the "Open Settings" state
            case .restricted: return (.off, [])                                // managed Mac: nothing to offer
            }
        }
    }

    private static func camera(_ phase: MirrorPhase, _ event: CameraEvent) -> (MirrorPhase, [MirrorEffect]) {
        switch (phase, event) {
        case (.starting(let id), .started(let started)) where id == started:
            return (.running(deviceID: id), [])
        case (.starting, .started), (.running, .started):
            return (phase, [])                                                 // a superseded start
        case (_, .started):
            return (phase, [.stop])                                            // started after a halt: release it
        case (.starting, .failed(let error)), (.running, .failed(let error)):
            return (.problem(error), [.stop])
        case (.starting, .stoppedBySystem), (.running, .stoppedBySystem):
            return (.off, [.stop])
        case (_, .failed), (_, .stoppedBySystem):
            return (phase, [])
        }
    }

    private static func devicesChanged(_ phase: MirrorPhase, _ inputs: MirrorInputs) -> (MirrorPhase, [MirrorEffect]) {
        switch phase {
        case .starting(let id), .running(let id):
            // The camera in use went away: say so, never switch to another camera on our own.
            guard inputs.connectedIDs.contains(id) else { return (.problem(.disconnected), [.stop]) }
            guard let camera = inputs.camera else { return (.problem(.noCamera), [.stop]) }
            if camera.isSuspended { return (.problem(.suspended), [.stop]) }
            guard camera.id != id else { return (phase, []) }
            // The user picked another camera in the menu, or (Automatic) the system's preferred camera changed:
            // the camera is already on by the user's click, so follow the choice (Apple's guidance for
            // `systemPreferredCamera`).
            return (.starting(deviceID: camera.id), [.start(deviceID: camera.id)])
        case .problem(.noCamera), .problem(.suspended):
            guard let camera = inputs.camera, !camera.isSuspended else { return (phase, []) }
            return (.off, [])                                                  // usable again: wait for a click
        case .off, .requestingAccess, .problem:
            return (phase, [])
        }
    }

    // MARK: Helpers

    /// Starts the resolved camera, or explains why it cannot.
    private static func start(_ inputs: MirrorInputs) -> (MirrorPhase, [MirrorEffect]) {
        guard let camera = inputs.camera else { return (.problem(.noCamera), []) }
        guard !camera.isSuspended else { return (.problem(.suspended), []) }
        return (.starting(deviceID: camera.id), [.start(deviceID: camera.id)])
    }
}
