// What the card shows for each state (DESIGN.md §7.4, §6.8) and when the hover toolbar appears.
import CrannyCore
import Testing
@testable import CrannyMirror

@MainActor struct MirrorPresentationTests {
    private func make(_ phase: MirrorPhase = .off, _ auth: PermissionStatus = .granted,
                      camera: CameraDevice? = Cameras.builtIn, loaded: Bool = true, live: Bool = true) -> MirrorPresentation {
        MirrorPresentation.make(phase: phase, authorization: auth, camera: camera, devicesLoaded: loaded, isLive: live)
    }

    @Test func offInvitesAClick() {
        let p = make()
        #expect(p.message == MirrorCopy.previewCamera)
        #expect(p.action == .turnOn)
        #expect(!p.showsFeed && !p.isOn)
        #expect(p.accessibilityValue == MirrorCopy.off)
        #expect(p.accessibilityHint == MirrorCopy.turnOnHint)
    }

    @Test func runningShowsTheFeedAndReadsOn() {
        let p = make(.running(deviceID: Cameras.builtIn.id))
        #expect(p.showsFeed && p.isOn)
        #expect(p.action == .turnOff)
        #expect(p.accessibilityValue == MirrorCopy.on)       // "Camera preview, on"
        #expect(p.accessibilityHint == MirrorCopy.turnOffHint)
    }

    @Test func stagesAlwaysShowTheRestingCard() {
        for phase in [MirrorPhase.running(deviceID: "x"), .problem(.sessionFailed), .requestingAccess] {
            let p = make(phase, .denied, live: false)
            #expect(p == MirrorPresentation(message: MirrorCopy.previewCamera))
            #expect(p.action == nil)
        }
    }

    @Test func startingShowsTheQuietLoadingGlyph() {
        let p = make(.starting(deviceID: "x"))
        #expect(p.glyph == .loading)
        #expect(p.action == nil)
        #expect(p.message == MirrorCopy.previewCamera)       // no text change while it starts
    }

    @Test func permissionStates() {
        #expect(make(.requestingAccess).message == MirrorCopy.waitingForAccess)
        let denied = make(.off, .denied)
        #expect(denied.message == MirrorCopy.accessOff)
        #expect(denied.actionTitle == MirrorCopy.allowCamera)
        #expect(denied.accessibilityHint == MirrorCopy.openSettingsHint)
        let restricted = make(.off, .restricted)
        #expect(restricted.message == MirrorCopy.accessRestricted)
        #expect(restricted.action == nil)
    }

    @Test func cameraStates() {
        #expect(make(camera: nil).message == MirrorCopy.noCamera)
        #expect(make(camera: nil, loaded: false).message == MirrorCopy.previewCamera)   // unknown is not "none"
        let lid = make(camera: CameraDevice(id: "b", name: "B", kind: .builtIn, isSuspended: true))
        #expect(lid.message == MirrorCopy.unavailable)
        #expect(lid.detail == MirrorCopy.lidClosed)
        #expect(lid.action == nil)
        #expect(lid.accessibilityValue == "\(MirrorCopy.unavailable), \(MirrorCopy.lidClosed)")
        // A USB camera with a shut privacy cover is suspended too, but no lid is involved.
        let shutter = make(camera: CameraDevice(id: "u", name: "U", kind: .external, isSuspended: true))
        #expect(shutter.detail == nil)
    }

    @Test func problemsExplainAndOfferARetry() {
        for error in [MirrorError.disconnected, .sessionFailed] {
            let p = make(.problem(error))
            #expect(p.glyph == .problem)
            #expect(p.message == MirrorCopy.message(for: error))
            #expect(p.actionTitle == MirrorCopy.tryAgain)
            #expect(p.action == .turnOn)
        }
        #expect(make(.problem(.notAuthorized)).action == .openSettings)
        #expect(MirrorError.sessionFailed.errorDescription == MirrorCopy.stopped)
    }

    @Test func everyStateHasText() {
        let phases: [MirrorPhase] = [.off, .requestingAccess, .starting(deviceID: "x"), .problem(.noCamera), .problem(.suspended),
                                     .problem(.disconnected), .problem(.notAuthorized), .problem(.sessionFailed)]
        for phase in phases {
            for auth in [PermissionStatus.granted, .denied, .restricted, .notDetermined, .unknown] {
                #expect(!make(phase, auth).message.isEmpty, "\(phase) \(auth)")
            }
        }
    }

    // MARK: Toolbar

    @Test func toolbarNeedsFramesAndIsNeverHoverOnly() {
        #expect(!MirrorVisibility.showsToolbar(isRunning: false, isHovered: true, isFocused: true, voiceOverRunning: true))
        #expect(!MirrorVisibility.showsToolbar(isRunning: true, isHovered: false, isFocused: false, voiceOverRunning: false))
        #expect(MirrorVisibility.showsToolbar(isRunning: true, isHovered: true, isFocused: false, voiceOverRunning: false))
        #expect(MirrorVisibility.showsToolbar(isRunning: true, isHovered: false, isFocused: true, voiceOverRunning: false))
        #expect(MirrorVisibility.showsToolbar(isRunning: true, isHovered: false, isFocused: false, voiceOverRunning: true))
        #expect(MirrorVisibility.showsToolbar(isRunning: true, isHovered: false, isFocused: false, voiceOverRunning: false, forced: true))
    }
}
