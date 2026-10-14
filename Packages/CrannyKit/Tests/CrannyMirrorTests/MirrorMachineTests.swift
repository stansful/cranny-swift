// The reducer alone: every privacy rule of DESIGN.md §7.4 / ARCHITECTURE.md §7.5 as a transition.
import CrannyCore
import Testing
@testable import CrannyMirror

@MainActor struct MirrorMachineTests {
    private let camera = Cameras.builtIn
    private func inputs(_ auth: PermissionStatus = .granted, camera: CameraDevice? = Cameras.builtIn,
                        devices: [CameraDevice]? = nil, eligible: Bool = true) -> MirrorInputs {
        MirrorInputs(authorization: auth, camera: camera, devices: devices, isEligible: eligible)
    }

    // MARK: Tap

    @Test func tapStartsTheResolvedCameraWhenGranted() {
        let (phase, effects) = MirrorMachine.reduce(.off, .tap, inputs())
        #expect(phase == .starting(deviceID: camera.id))
        #expect(effects == [.start(deviceID: camera.id)])
    }

    @Test func tapIsIgnoredWhenTheWidgetIsNotLive() {
        for phase in [MirrorPhase.off, .problem(.sessionFailed)] {
            let (next, effects) = MirrorMachine.reduce(phase, .tap, inputs(eligible: false))
            #expect(next == phase)
            #expect(effects.isEmpty)
        }
    }

    @Test(arguments: [PermissionStatus.notDetermined, .unknown])
    func tapAsksForAccessAndHoldsThePanelOpen(_ status: PermissionStatus) {
        let (phase, effects) = MirrorMachine.reduce(.off, .tap, inputs(status))
        #expect(phase == .requestingAccess)
        #expect(effects == [.holdOpen(true), .requestAccess])
    }

    @Test func tapWithAccessDeniedOpensSystemSettingsAndNeverStarts() {
        let (phase, effects) = MirrorMachine.reduce(.off, .tap, inputs(.denied))
        #expect(phase == .off)
        #expect(effects == [.openSystemSettings])
    }

    @Test func tapWithAccessRestrictedDoesNothing() {
        let (phase, effects) = MirrorMachine.reduce(.off, .tap, inputs(.restricted))
        #expect(phase == .off)
        #expect(effects.isEmpty)
    }

    @Test func tapWithoutACameraExplains() {
        #expect(MirrorMachine.reduce(.off, .tap, inputs(camera: nil)) == (.problem(.noCamera), []))
        let suspended = CameraDevice(id: "x", name: "x", kind: .builtIn, isSuspended: true)
        #expect(MirrorMachine.reduce(.off, .tap, inputs(camera: suspended)) == (.problem(.suspended), []))
    }

    @Test func tapOnARunningMirrorTurnsItOff() {
        #expect(MirrorMachine.reduce(.running(deviceID: camera.id), .tap, inputs()) == (.off, [.stop]))
    }

    @Test func tapWhileBusyIsIgnored() {
        for phase in [MirrorPhase.requestingAccess, .starting(deviceID: camera.id)] {
            #expect(MirrorMachine.reduce(phase, .tap, inputs()) == (phase, []))
        }
    }

    @Test func tapAfterAProblemTriesAgain() {
        let (phase, effects) = MirrorMachine.reduce(.problem(.sessionFailed), .tap, inputs())
        #expect(phase == .starting(deviceID: camera.id))
        #expect(effects == [.start(deviceID: camera.id)])
    }

    // MARK: Permission answer

    @Test func grantedAnswerReleasesTheHoldAndStarts() {
        let (phase, effects) = MirrorMachine.reduce(.requestingAccess, .accessResult(.granted), inputs())
        #expect(phase == .starting(deviceID: camera.id))
        #expect(effects == [.holdOpen(false), .start(deviceID: camera.id)])
    }

    @Test func deniedAnswerReleasesTheHold() {
        #expect(MirrorMachine.reduce(.requestingAccess, .accessResult(.denied), inputs(.denied)) == (.off, [.holdOpen(false)]))
    }

    @Test func grantedAnswerAfterThePanelClosedNeverStarts() {
        // Closed while the prompt was up: the halt already released the hold; the late answer changes nothing.
        let (halted, haltEffects) = MirrorMachine.reduce(.requestingAccess, .halt, inputs())
        #expect(halted == .off)
        #expect(haltEffects == [.holdOpen(false)])
        #expect(MirrorMachine.reduce(halted, .accessResult(.granted), inputs()) == (.off, []))
        // Not visible any more when the answer arrives (e.g. page changed without a halt yet).
        #expect(MirrorMachine.reduce(.requestingAccess, .accessResult(.granted), inputs(eligible: false)) == (.off, [.holdOpen(false)]))
    }

    // MARK: Hardware answers

    @Test func startedCompletesTheMatchingStart() {
        #expect(MirrorMachine.reduce(.starting(deviceID: camera.id), .camera(.started(deviceID: camera.id)), inputs())
                == (.running(deviceID: camera.id), []))
        // A superseded start (the user switched cameras meanwhile) is ignored.
        #expect(MirrorMachine.reduce(.starting(deviceID: "b"), .camera(.started(deviceID: "a")), inputs())
                == (.starting(deviceID: "b"), []))
    }

    @Test func startedAfterAHaltIsReleasedImmediately() {
        #expect(MirrorMachine.reduce(.off, .camera(.started(deviceID: camera.id)), inputs()) == (.off, [.stop]))
    }

    @Test(arguments: [MirrorError.sessionFailed, .disconnected, .suspended, .notAuthorized])
    func failuresStopAndExplain(_ error: MirrorError) {
        for phase in [MirrorPhase.starting(deviceID: camera.id), .running(deviceID: camera.id)] {
            #expect(MirrorMachine.reduce(phase, .camera(.failed(error)), inputs()) == (.problem(error), [.stop]))
        }
        #expect(MirrorMachine.reduce(.off, .camera(.failed(error)), inputs()) == (.off, []))
    }

    @Test func aSessionStoppedByTheSystemGoesOff() {
        #expect(MirrorMachine.reduce(.running(deviceID: camera.id), .camera(.stoppedBySystem), inputs()) == (.off, [.stop]))
    }

    // MARK: Halt (close, page change, lock, sleep, hidden)

    @Test func haltAlwaysEndsOffAndReleasesWhatIsHeld() {
        #expect(MirrorMachine.reduce(.off, .halt, inputs()) == (.off, []))
        #expect(MirrorMachine.reduce(.requestingAccess, .halt, inputs()) == (.off, [.holdOpen(false)]))
        #expect(MirrorMachine.reduce(.starting(deviceID: camera.id), .halt, inputs()) == (.off, [.stop]))
        #expect(MirrorMachine.reduce(.running(deviceID: camera.id), .halt, inputs()) == (.off, [.stop]))
        #expect(MirrorMachine.reduce(.problem(.disconnected), .halt, inputs()) == (.off, []))
    }

    @Test func becomingVisibleAgainNeverStartsByItself() {
        // No event other than a tap (or a granted prompt the tap opened) ever produces `.start`.
        let quiet: [MirrorEvent] = [.devicesChanged, .halt, .accessResult(.granted), .camera(.failed(.sessionFailed)),
                                    .camera(.failed(.suspended)), .camera(.stoppedBySystem)]
        for event in quiet {
            for phase in [MirrorPhase.off, .problem(.noCamera), .problem(.suspended), .problem(.sessionFailed)] {
                let (_, effects) = MirrorMachine.reduce(phase, event, inputs())
                #expect(!effects.contains(.start(deviceID: camera.id)), "\(phase) + \(event)")
            }
        }
    }

    // MARK: Devices changed

    @Test func runningFollowsANewChoice() {
        let (phase, effects) = MirrorMachine.reduce(.running(deviceID: camera.id), .devicesChanged,
                                                    inputs(camera: Cameras.iPhone, devices: [camera, Cameras.iPhone]))
        #expect(phase == .starting(deviceID: Cameras.iPhone.id))
        #expect(effects == [.start(deviceID: Cameras.iPhone.id)])
    }

    @Test func runningCameraUnpluggedStopsWithAMessage() {
        let (phase, effects) = MirrorMachine.reduce(.running(deviceID: Cameras.usb.id), .devicesChanged,
                                                    inputs(camera: camera, devices: [camera]))
        #expect(phase == .problem(.disconnected))
        #expect(effects == [.stop])
    }

    @Test func runningCameraSuspendedStops() {
        let suspended = Cameras.builtInSuspended
        #expect(MirrorMachine.reduce(.running(deviceID: camera.id), .devicesChanged, inputs(camera: suspended))
                == (.problem(.suspended), [.stop]))
    }

    @Test func runningCameraSuspendedWithAnotherWorkingCameraStopsAndOffersIt() {
        // The lid closed on the built-in camera while a USB camera is attached: stop, never switch by itself, and
        // leave the card at "Preview camera" so one click starts the USB camera (never a dead end).
        let lid = inputs(camera: Cameras.usb, devices: [Cameras.builtInSuspended, Cameras.usb])
        #expect(MirrorMachine.reduce(.running(deviceID: camera.id), .devicesChanged, lid) == (.off, [.stop]))
        #expect(MirrorMachine.reduce(.running(deviceID: camera.id), .camera(.failed(.suspended)), lid) == (.off, [.stop]))
        // The list has not caught up yet (it still shows the built-in camera working): explain for now.
        #expect(MirrorMachine.reduce(.running(deviceID: camera.id), .camera(.failed(.suspended)), inputs())
                == (.problem(.suspended), [.stop]))
        // Once it has, the message clears.
        #expect(MirrorMachine.reduce(.problem(.suspended), .devicesChanged, lid) == (.off, []))
    }

    @Test func unchangedDevicesKeepRunning() {
        #expect(MirrorMachine.reduce(.running(deviceID: camera.id), .devicesChanged, inputs()) == (.running(deviceID: camera.id), []))
    }

    @Test func aCameraArrivingClearsNoCameraButWaitsForAClick() {
        #expect(MirrorMachine.reduce(.problem(.noCamera), .devicesChanged, inputs()) == (.off, []))
        #expect(MirrorMachine.reduce(.problem(.suspended), .devicesChanged, inputs()) == (.off, []))
        #expect(MirrorMachine.reduce(.problem(.noCamera), .devicesChanged, inputs(camera: nil)) == (.problem(.noCamera), []))
        // "Camera disconnected" stays true until the user tries again.
        #expect(MirrorMachine.reduce(.problem(.disconnected), .devicesChanged, inputs()) == (.problem(.disconnected), []))
    }
}
