// CrannyOnboarding/Model/WelcomeFlow.swift — the Welcome window's state and rules (DESIGN.md §12.1): the
// current step, real detection on the notch through `NotchControl.addEventObserver`, the choices each step
// writes (open mode, hover delay, Home layout — instantly, ARCHITECTURE.md D14), permission rows, the practice
// notch, and how the window ends. Views read it; only it writes settings. Testable with `CrannyServices.preview()`.
import AppKit
import CrannyCore
import Foundation
import Observation
import os
import SwiftUI

private let log = Log.logger(.onboarding)

@MainActor @Observable final class WelcomeFlow {
    let plan: WelcomePlan
    let stage: StageScene
    private(set) var step: WelcomeStep
    /// Direction of the last move (step transitions slide the way you go).
    private(set) var movedForward = true
    /// Esc asks "Skip setup?" before anything is skipped.
    var isConfirmingSkip = false
    /// Step 2: the ways in the person really used on the real notch.
    private(set) var detected: Set<OpenMethod> = []
    /// Step 3: the practice moves done.
    private(set) var pulledDown = false
    private(set) var swipedSideways = false
    /// Step 3 practises the sideways swipe only while something plays (DESIGN.md §12.1).
    private(set) var practisesTrackSwipe = false
    /// Step 6: Launch at login (applied when setup finishes, never on the way).
    var launchesAtLogin: Bool
    private(set) var isFinished = false

    @ObservationIgnored let registry: ModuleRegistry
    @ObservationIgnored private let permissions: any PermissionGateway
    @ObservationIgnored private let coach: any TipPresenter
    @ObservationIgnored private let version: String
    @ObservationIgnored private let onFinish: @MainActor (WelcomeOutcome) -> Void
    @ObservationIgnored private var practice = GesturePractice(allowsTrackSwipe: false)
    @ObservationIgnored private var observer: UUID?
    /// Step 5: back from System Settings, statuses may have changed (event-driven, no polling).
    @ObservationIgnored private var activationObserver: (any NSObjectProtocol)?
    @ObservationIgnored private var reduceMotion = false
    /// Rows whose Allow was pressed (an undecidable answer then reads "asks later", not "Allow" again).
    private var requested: Set<PermissionGroup> = []
    /// The notch is open (mirrored on the stage, hides the coach mark).
    private var isNotchOpen = false

    init(registry: ModuleRegistry, permissions: any PermissionGateway, coach: any TipPresenter, stage: StageScene,
         initialStep: WelcomeStep = .hello, version: String = AppInfo.current().version,
         onFinish: @escaping @MainActor (WelcomeOutcome) -> Void) {
        self.registry = registry
        self.permissions = permissions
        self.coach = coach
        self.stage = stage
        self.version = version
        self.onFinish = onFinish
        plan = WelcomePlan(hasTrackpad: registry.services.environment.hasTrackpad)
        step = plan.resolve(initialStep)
        let settings = registry.services.settings
        let loginItem = registry.services.app.loginItem
        let firstRun = settings[CoreSettings.onboardingCompletedVersion] == nil
        launchesAtLogin = firstRun ? Self.canChangeLoginItem(loginItem) : Self.isOn(loginItem)
    }

    // MARK: Lifecycle

    /// Starts listening to the real notch and plays the current step. Call when the window appears.
    func start(reduceMotion: Bool) {
        self.reduceMotion = reduceMotion
        if observer == nil {
            observer = services.notch.addEventObserver { [weak self] event in self?.handle(event) }
        }
        enter(step)
    }

    /// Stops listening and hides everything outside the window. Idempotent.
    func stop() {
        if let observer { services.notch.removeEventObserver(observer) }
        observer = nil
        stopWatchingActivation()
        coach.hide()
        stage.stop()
    }

    // MARK: Navigation

    var stepNumber: Int { plan.number(of: step) }
    var stepCount: Int { plan.count }
    var canGoBack: Bool { plan.previous(before: step) != nil }
    var isLastStep: Bool { plan.next(after: step) == nil }

    /// Continue enables once the step was really done (steps 2 and 3); every other step is ready at once.
    var canContinue: Bool {
        switch step {
        case .openIt: !detected.isEmpty
        case .gestures: pulledDown || swipedSideways
        case .hello, .preset, .permissions, .done: true
        }
    }

    /// Steps 2 and 3 offer "Skip" until they are done (every step is skippable).
    var offersSkip: Bool { !canContinue }

    /// Continue (↩) or Skip: the next step; past the last step, setup is done.
    func goForward() {
        guard let next = plan.next(after: step) else { return finish(.done) }
        move(to: next, forward: true)
    }

    /// ⌘[.
    func goBack() {
        guard let previous = plan.previous(before: step) else { return }
        move(to: previous, forward: false)
    }

    /// Esc: asks "Skip setup?".
    func requestSkip() {
        guard !isFinished else { return }
        isConfirmingSkip = true
    }

    /// Ends the Welcome window. Records completion (also when skipped, so it is not shown again; it stays
    /// available from Settings ▸ About). "Done" opens the panel once; Launch at login applies unless skipped.
    func finish(_ outcome: WelcomeOutcome) {
        guard !isFinished else { return }
        isFinished = true
        isConfirmingSkip = false
        services.settings[CoreSettings.onboardingCompletedVersion] = version
        if outcome != .skipped { applyLaunchAtLogin() }
        stop()
        if outcome == .done { services.notch.open(page: .nook, focus: nil, reason: .programmatic) }
        log.info("welcome finished: \(String(describing: outcome), privacy: .public) at step \(self.step.rawValue, privacy: .public)")
        onFinish(outcome)
    }

    private func move(to next: WelcomeStep, forward: Bool) {
        leave(step)
        movedForward = forward
        step = next
        enter(next)
    }

    private func enter(_ step: WelcomeStep) {
        switch step {
        case .hello:
            services.notch.flash(symbol: StageGreeting.symbol, label: Self.greeting)
            stage.show(.greeting, reduceMotion: reduceMotion)
        case .openIt:
            stage.show(.idle, reduceMotion: reduceMotion)
            isNotchOpen = false
            showCoach()
        case .gestures:
            let playing = isPlaying
            practisesTrackSwipe = playing
            practice = GesturePractice(allowsTrackSwipe: playing,
                                       sensitivity: services.settings[CoreSettings.gestureSensitivity],
                                       invertsTrackSwipe: services.settings[CoreSettings.invertTrackSwipe])
            stage.show(.practice(withTrack: playing), reduceMotion: reduceMotion)
        case .preset:
            stage.show(.open, reduceMotion: reduceMotion)
        case .permissions:
            permissions.refresh()
            watchActivation()
            stage.show(.open, reduceMotion: reduceMotion)
        case .done:
            stage.show(.idle, reduceMotion: reduceMotion)
        }
    }

    private func leave(_ step: WelcomeStep) {
        if step == .openIt { coach.hide() }
        if step == .permissions { stopWatchingActivation() }
    }

    // MARK: Step 1 · Hello

    /// The label of the real notch's "Hi" (≤ 12 characters, `NotchControl.flash`).
    static var greeting: String { String(localized: "Hi", bundle: .module, comment: "Welcome step 1: the greeting the real notch shows (12 characters at most)") }

    /// "Wave again": the real notch and the stage say hi once more.
    func greetAgain() {
        guard step == .hello else { return }
        enter(.hello)
    }

    // MARK: Step 2 · Open it your way

    var openMethod: OpenMethod { OpenMethod(mode: services.settings[CoreSettings.openMode]) }
    var hoverDelay: HoverIntent.Delay { services.settings[CoreSettings.hoverDelay] }
    var openShortcut: String? { ShortcutText.openCranny(services.settings[CoreSettings.shortcuts]) }

    func choose(_ method: OpenMethod) {
        services.settings[CoreSettings.openMode] = method.mode
        showCoach()
    }

    func setHoverDelay(_ delay: HoverIntent.Delay) {
        services.settings[CoreSettings.hoverDelay] = delay
        if openMethod != .hover { choose(.hover) }
    }

    /// The coach mark's sentence for the chosen way in (DESIGN.md §12.1: "Rest the pointer here, or press ⌃⌥N").
    func coachContent() -> TipContent {
        let shortcut = openShortcut
        let text: String = switch (openMethod, shortcut != nil) {
        case (.hover, true): String(localized: "Rest the pointer here, or press", bundle: .module, comment: "Welcome step 2: coach mark under the real notch; followed by a key cap such as ⌃⌥N")
        case (.hover, false): String(localized: "Rest the pointer here", bundle: .module, comment: "Welcome step 2: coach mark under the real notch (no shortcut set)")
        case (.click, true): String(localized: "Click here, or press", bundle: .module, comment: "Welcome step 2: coach mark under the real notch; followed by a key cap such as ⌃⌥N")
        case (.click, false): String(localized: "Click here", bundle: .module, comment: "Welcome step 2: coach mark under the real notch (no shortcut set)")
        case (.shortcut, true): String(localized: "Press", bundle: .module, comment: "Welcome step 2: coach mark under the real notch; followed by a key cap such as ⌃⌥N")
        case (.shortcut, false): String(localized: "Set a shortcut in Settings ▸ Keyboard", bundle: .module, comment: "Welcome step 2: coach mark when the Open Cranny shortcut is turned off")
        }
        return TipContent(text: text, keys: shortcut)
    }

    private func showCoach() {
        guard step == .openIt, !isNotchOpen, !isFinished else { return }
        coach.show(coachContent(), under: services.notch.shapeFrameOnScreen())
    }

    // MARK: Step 3 · Gestures

    var isPlaying: Bool { services.nowPlaying?.nowPlaying?.isPlaying == true }

    /// Two-finger scroll over the stage (never reaches real media or the real notch).
    func handleScroll(_ sample: ScrollSample) {
        guard step == .gestures else { return }
        for effect in practice.handle(sample) {
            switch effect {
            case .follow(let translation):
                stage.setGesture(translation)
            case .open:
                services.haptics.play(.alignment)
                stage.setOpen(true)
                pulledDown = true
            case .close:
                services.haptics.play(.alignment)
                stage.setOpen(false)
            case .track(let gesture):
                services.haptics.play(.alignment)
                stage.swipeTrack(gesture)
                swipedSideways = true
            case .snapBack:
                stage.setGesture(.zero)
            }
        }
    }

    // MARK: Step 4 · Layout

    /// The preset Home matches now; nil for a layout of one's own (kept unless a preset is picked).
    var selectedPreset: NookPreset? { PresetLayout.matching(services.settings[CoreSettings.pages]) }

    func pick(_ preset: NookPreset) {
        let pages = services.settings[CoreSettings.pages]
        services.settings[CoreSettings.pages] = PresetLayout.applying(preset, to: pages)
        stage.refreshLayout()
    }

    // MARK: Step 5 · Permissions

    var permissionRows: [PermissionRow] {
        let items = PresetLayout.homeItems(services.settings[CoreSettings.pages])
        return PermissionPlan.rows(uses: registry.permissionUses, modules: PermissionPlan.modules(for: items))
    }

    func state(of row: PermissionRow) -> PermissionRowState {
        PermissionRowState.combining(row.kinds.map { permissions.status($0) }, requested: requested.contains(row.group))
    }

    /// "Allow": the system prompt, then and there (one kind after the other).
    func allow(_ row: PermissionRow) async {
        requested.insert(row.group)
        for kind in row.kinds where permissions.status(kind) != .granted {
            await permissions.request(kind)
        }
    }

    func openSystemSettings(_ row: PermissionRow) {
        guard let kind = row.kinds.first else { return }
        permissions.openSystemSettings(kind)
    }

    private func watchActivation() {
        guard activationObserver == nil else { return }
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.permissions.refresh() }                  // queue: .main
        }
    }

    private func stopWatchingActivation() {
        if let activationObserver { NotificationCenter.default.removeObserver(activationObserver) }
        activationObserver = nil
    }

    // MARK: Step 6 · You're set

    var loginItem: LoginItemState { services.app.loginItem }
    var canChangeLoginItem: Bool { Self.canChangeLoginItem(loginItem) }

    var checksForUpdates: Bool {
        get { services.settings[CoreSettings.checksForUpdates] }
        set { services.settings[CoreSettings.checksForUpdates] = newValue }
    }

    var cheatSheet: [CheatSheetEntry] { CheatSheetEntry.sheet(openCranny: openShortcut) }

    private func applyLaunchAtLogin() {
        guard canChangeLoginItem, launchesAtLogin != Self.isOn(loginItem) else { return }
        services.app.setLaunchAtLogin(launchesAtLogin)
    }

    private static func isOn(_ state: LoginItemState) -> Bool { state == .enabled || state == .requiresApproval }
    private static func canChangeLoginItem(_ state: LoginItemState) -> Bool {
        if case .unavailable = state { return false }
        return true
    }

    // MARK: Events from the real notch

    private var services: CrannyServices { registry.services }

    func handle(_ event: NotchEvent) {
        guard step == .openIt, !isFinished else { return }
        switch event {
        case .opened:
            isNotchOpen = true
            coach.hide()
            stage.setOpen(true)
            if let method = OpenMethod.detected(by: event), detected.insert(method).inserted {
                AccessibilityNotification.Announcement(Self.detectedAnnouncement(method)).post()
            }
        case .closed:
            isNotchOpen = false
            stage.setOpen(false)
            // The shell writes the closed shape after emitting the event: place the coach mark on the next turn.
            Task { [weak self] in self?.showCoach() }
        default:
            break
        }
    }

    private static func detectedAnnouncement(_ method: OpenMethod) -> String {
        switch method {
        case .hover: String(localized: "Opened by resting the pointer", bundle: .module, comment: "Welcome step 2: VoiceOver announcement after the real notch opened")
        case .click: String(localized: "Opened with a click", bundle: .module, comment: "Welcome step 2: VoiceOver announcement after the real notch opened")
        case .shortcut: String(localized: "Opened with the shortcut", bundle: .module, comment: "Welcome step 2: VoiceOver announcement after the real notch opened")
        }
    }
}
