// CrannyMirror/Model/MirrorModel.swift — owns the Mirror's state: runs `MirrorMachine`, executes its effects
// against the camera, permission and notch ports, and stops everything the moment the widget may no longer show
// the camera (ARCHITECTURE.md §7.5: close, page change, sleep, lock, previews).
import CrannyCore
import Foundation
import Observation
import os

private let log = Log.logger(.mirror)

@MainActor @Observable final class MirrorModel {
    /// Why the camera was stopped without a click (logged; the result is always `.off`).
    enum HaltReason: String { case closed, pageChanged, locked, systemSleep, hidden, terminating }

    /// The reason passed to `NotchControl.setHoldOpen` while the system camera prompt is up and until the user is
    /// back after answering it (§4.5, MirrorMachine.swift).
    static let permissionHold = "mirror.permission"
    /// After answering the camera prompt the user has this long to come back to the widget before the hold ends
    /// anyway, so the panel closes as usual if they went elsewhere (a pointer inside the panel keeps it open).
    static let returnTimeout: Duration = .seconds(10)
    /// After "Open Settings", appearances re-read the camera permission for this long (the user may allow the
    /// camera in System Settings and come back by hovering, which never activates the app).
    static let settingsRecheckWindow: Duration = .seconds(600)

    private(set) var phase: MirrorPhase = .off
    /// What the preview draws; set when the camera reports `.started`, cleared on stop.
    private(set) var feed: CameraFeed?
    /// The camera list (observable: the toolbar menu and the options follow hot-plug).
    let catalog: CameraCatalog

    /// Internal (not private) so tests can check which parts the live module uses.
    @ObservationIgnored let controller: any CameraControlling
    @ObservationIgnored let authorization: any CameraAuthorizing
    @ObservationIgnored private let settings: SettingsStore
    @ObservationIgnored private let notch: any NotchControl
    @ObservationIgnored private let environment: any SystemEnvironment
    /// Live widget views on screen (each has its own token: two panels or a re-created view never confuse it).
    @ObservationIgnored private var visibleViews: Set<UUID> = []
    @ObservationIgnored private var isHoldingOpen = false
    /// Ends the permission hold if the user does not come back (`returnTimeout`; tests shorten it).
    @ObservationIgnored var returnTimeout = MirrorModel.returnTimeout
    @ObservationIgnored private var returnTask: Task<Void, Never>?
    /// When "Open Settings" last sent the user to System Settings (see `settingsRecheckWindow`).
    @ObservationIgnored private var settingsOpenedAt: ContinuousClock.Instant?
    @ObservationIgnored private var observations: [ObservationToken] = []
    @ObservationIgnored private var notchObserver: UUID?

    #if DEBUG
    /// Visual QA only (`--qa-mirror`): start as soon as a live widget appears, without a click.
    @ObservationIgnored var startsWhenVisibleForQA = false
    /// Visual QA only: keep the hover toolbar visible while running (screenshots cannot hover).
    var showsToolbarForQA = false
    #endif

    init(settings: SettingsStore, notch: any NotchControl, environment: any SystemEnvironment,
         catalog: CameraCatalog, controller: any CameraControlling, authorization: any CameraAuthorizing) {
        self.settings = settings; self.notch = notch; self.environment = environment
        self.catalog = catalog; self.controller = controller; self.authorization = authorization
        controller.onEvent = { [weak self] event in self?.handle(event) }
        catalog.onChange = { [weak self] in self?.dispatch(.devicesChanged) }
    }

    // MARK: Derived state

    /// Camera permission (observable; reading it never prompts).
    var authorizationStatus: PermissionStatus { authorization.status }

    /// The camera the widget shows: the user's pick if connected, else the system's preferred camera.
    var camera: CameraDevice? {
        CameraCatalog.resolve(selectedID: settings[MirrorSettings.cameraID], devices: catalog.devices,
                              systemPreferredID: catalog.systemPreferredID)
    }

    /// The user's pick in the camera menu (nil = Automatic). Changing it while running switches cameras.
    var selectedCameraID: String? {
        get { settings[MirrorSettings.cameraID] }
        set { settings[MirrorSettings.cameraID] = newValue }
    }

    var isMirrored: Bool {
        get { settings[MirrorSettings.isMirrored] }
        set { settings[MirrorSettings.isMirrored] = newValue }
    }

    /// What a widget with this context shows (`MirrorPresentation.make`).
    func presentation(isLive: Bool) -> MirrorPresentation {
        MirrorPresentation.make(phase: phase, authorization: authorizationStatus, camera: camera,
                                devicesLoaded: catalog.isLoaded, isLive: isLive)
    }

    /// The camera may run: a live widget is on screen, the screen is unlocked and the displays are awake.
    var isEligible: Bool {
        !visibleViews.isEmpty && !environment.isScreenLocked && !environment.areDisplaysAsleep
    }

    // MARK: Lifecycle (MirrorModule)

    /// `registry.onLaunch`: observe the notch and the environment. No hardware, no enumeration.
    func activate() {
        guard notchObserver == nil else { return }
        notchObserver = notch.addEventObserver { [weak self] event in
            switch event {
            case .closed: self?.halt(.closed)
            case .pageChanged: self?.halt(.pageChanged)
            default: break
            }
        }
        observations = [
            observe({ [environment] in environment.isScreenLocked || environment.areDisplaysAsleep }) { [weak self] blocked in
                if blocked { self?.halt(.locked) }
            },
            observe({ [settings] in settings[MirrorSettings.cameraID] }) { [weak self] _ in
                self?.dispatch(.devicesChanged)
            },
        ]
    }

    /// `registry.onTerminate`: release the camera and every observer.
    func shutdown() {
        halt(.terminating)
        if let notchObserver { notch.removeEventObserver(notchObserver) }
        notchObserver = nil
        observations.forEach { $0.cancel() }
        observations.removeAll()
        catalog.deactivate()
    }

    // MARK: Widget views

    /// A widget view appeared, or its context changed. Only a live view counts as visible (the real open panel:
    /// not a Settings or onboarding stage, a `#Preview` or layout editing, `MirrorVisibility.isLive`); a view
    /// that stops being live counts as gone, which stops the camera if it was the last one.
    func viewAppeared(_ id: UUID, context: WidgetContext) {
        guard MirrorVisibility.isLive(context) else { return viewDisappeared(id) }
        guard visibleViews.insert(id).inserted else { return }
        catalog.activate()
        recheckAccessAfterSettings()
        #if DEBUG
        if startsWhenVisibleForQA, phase == .off { Task { await tap() } }
        #endif
    }

    /// A widget view left the screen (panel closed, page changed, layout editing began).
    func viewDisappeared(_ id: UUID) {
        guard visibleViews.remove(id) != nil else { return }
        if visibleViews.isEmpty { halt(.hidden) }
    }

    /// The pointer is over the card, or keyboard focus is in the widget. After the camera prompt was answered
    /// this means the user is back, which ends the permission hold.
    func userReturned() {
        guard isHoldingOpen else { return }
        dispatch(.returned)
    }

    /// The card was clicked (or its VoiceOver/keyboard action used): start, stop, or open System Settings.
    func tap() async {
        guard isEligible else { return }
        userReturned()
        switch phase {
        case .off, .problem:
            await catalog.ensureLoaded()
            // A click is the moment to re-read the permission (never the panel opening, `settingsRecheckWindow`).
            settingsOpenedAt = nil
            authorization.refresh(force: phase == .problem(.notAuthorized))
        case .requestingAccess, .starting, .running:
            break
        }
        dispatch(.tap)
    }

    /// Stops the camera (if any) and returns to `.off`; the next start needs a click.
    func halt(_ reason: HaltReason) {
        if phase != .off { log.info("halt: \(reason.rawValue, privacy: .public)") }
        dispatch(.halt)
    }

    // MARK: Machine

    private func handle(_ event: CameraEvent) {
        if case .started = event { feed = controller.feed }
        dispatch(.camera(event))
        // The list may not know yet that the camera is suspended (lid, shutter): re-read it, so the card offers
        // another working camera or clears the message when it resumes.
        if event == .failed(.suspended) { catalog.requestRefresh() }
    }

    /// Only after "Open Settings" (the user may have allowed the camera there): `PermissionsCenter.refresh`
    /// re-queries every permission, which never belongs on the panel-open path otherwise.
    private func recheckAccessAfterSettings() {
        guard let opened = settingsOpenedAt else { return }
        guard ContinuousClock.now - opened < Self.settingsRecheckWindow, authorization.status != .granted else {
            settingsOpenedAt = nil
            return
        }
        authorization.refresh(force: false)
    }

    private func dispatch(_ event: MirrorEvent) {
        let inputs = MirrorInputs(authorization: authorization.status, camera: camera, devices: catalog.devices,
                                  isEligible: isEligible, isHoldingOpen: isHoldingOpen)
        let (next, effects) = MirrorMachine.reduce(phase, event, inputs)
        if next != phase {
            log.info("mirror: \(self.phase.logName, privacy: .public) → \(next.logName, privacy: .public)")
            phase = next
        }
        effects.forEach(run)
    }

    private func run(_ effect: MirrorEffect) {
        switch effect {
        case .requestAccess:
            Task { [weak self, authorization] in
                let status = await authorization.request()
                self?.dispatch(.accessResult(status))
            }
        case .start(let deviceID):
            controller.start(deviceID: deviceID)
        case .stop:
            controller.stop()
            feed = nil
        case .holdOpen(let hold):
            returnTask?.cancel()
            returnTask = nil
            guard hold != isHoldingOpen else { return }
            isHoldingOpen = hold
            notch.setHoldOpen(hold, reason: Self.permissionHold)
        case .awaitReturn:
            guard isHoldingOpen else { return }
            returnTask?.cancel()
            returnTask = Task { [weak self, returnTimeout] in
                try? await Task.sleep(for: returnTimeout)
                guard !Task.isCancelled else { return }
                self?.dispatch(.returned)
            }
        case .openSystemSettings:
            settingsOpenedAt = .now
            authorization.openSystemSettings()
        }
    }
}

// MARK: - Previews

extension MirrorModel {
    /// Shows `phase` directly, for #Previews (`MirrorModel.preview`). Only a model built on the sample camera
    /// accepts it, so no path can fake a running state over the real hardware.
    func showPreviewState(_ phase: MirrorPhase) {
        guard controller is SampleCameraController else { return }
        self.phase = phase
        feed = phase.usesCamera ? .sample : nil
    }
}
