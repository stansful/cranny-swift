// CrannyOnboarding/Tutorial/TutorialController.swift — the 5-step interactive tutorial in the real notch
// (DESIGN.md §12.2). Intra-shell interface fixed by WP0 (ARCHITECTURE.md §10.0): `init(registry:)`, `start()`,
// `stop()`, `isRunning` (observable, so a menu can offer "Skip tour" while it runs). Every step completes on real
// detection through `NotchControl.addEventObserver`, with a ✓ bounce, an `.alignment` haptic and a VoiceOver
// announcement. The bubble sits under `NotchControl.shapeFrameOnScreen()` and shows only while the notch does
// (`TipPresentation`, observed: no timers, no polling). Ways out: "Skip tour" on the bubble, the same command in
// ⌘K (`TutorialCommands`), and a step that waits longer than `idleLimit` ends the tour (one sleep per step).
import AppKit
import CrannyCore
import Foundation
import Observation
import os
import SwiftUI

private let log = Log.logger(.onboarding)

/// Runs the interactive tutorial in the real notch (DESIGN.md §12.2); owned by the shell, started from the
/// Welcome window, the menu bar and Settings ▸ About ("Replay tutorial").
@MainActor @Observable public final class TutorialController {
    /// True from `start()` until the tour ends, is skipped or `stop()`.
    public private(set) var isRunning = false

    /// What the bubble shows.
    private enum Showing: Equatable {
        /// A step, waiting for the person or (`done`) just done.
        case step(TutorialStep, done: Bool)
        /// The closing bubble after the last step.
        case farewell
    }

    private let registry: ModuleRegistry
    private let tip: TipRenderer
    /// How long the ✓ of a finished step stays before the next step.
    private let celebration: Duration
    /// How long the closing bubble stays.
    private let farewell: Duration
    /// A step that waits this long ends the tour (it can be replayed): the bubble never lingers for ever, and a
    /// step someone cannot do (a file drag without a pointer) never traps them.
    private let idleLimit: Duration
    @ObservationIgnored private var run = TutorialRun(includesTrackSwipe: false)
    /// Observed (with the settings it reads) by the bubble's own observation, so the sentence keeps up.
    private var showing: Showing?
    @ObservationIgnored private var observer: UUID?
    @ObservationIgnored private var screenObserver: (any NSObjectProtocol)?
    @ObservationIgnored private var surroundings: ObservationToken?
    @ObservationIgnored private var pending: Task<Void, Never>?
    @ObservationIgnored private var idle: Task<Void, Never>?

    /// The registry gives the tutorial `NotchControl` (bubble anchor, step detection) and the settings.
    public convenience init(registry: ModuleRegistry) {
        self.init(registry: registry, presenter: TipPanelPresenter())
    }

    init(registry: ModuleRegistry, presenter: any TipPresenter, celebration: Duration = .milliseconds(900),
         farewell: Duration = .seconds(5), idleLimit: Duration = .seconds(180)) {
        self.registry = registry
        tip = TipRenderer(presenter: presenter)
        self.celebration = celebration
        self.farewell = farewell
        self.idleLimit = idleLimit
        registry.add(commands: TutorialCommands(tutorial: self))
    }

    /// Starts (or restarts) the tour at its first step.
    public func start() { begin(at: 0) }

    #if DEBUG
    /// Visual QA (`--qa-tutorial <n>`): starts the tour at step `n` (1-based). Records nothing.
    public func startForVisualQA(atStep step: Int) { begin(at: step - 1) }
    #endif

    /// Ends the tour at once (no completion recorded).
    public func stop() {
        pending?.cancel()
        pending = nil
        idle?.cancel()
        idle = nil
        if let observer { services.notch.removeEventObserver(observer) }
        observer = nil
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
        surroundings?.cancel()
        surroundings = nil
        showing = nil
        tip.hide()
        isRunning = false
    }

    // MARK: Run

    private var services: CrannyServices { registry.services }
    private var isPlaying: Bool { services.nowPlaying?.nowPlaying?.isPlaying == true }
    private var isCelebrating: Bool {
        if case .step(_, done: true)? = showing { return true }
        return false
    }

    private func begin(at index: Int) {
        stop()
        isRunning = true
        run = TutorialRun(includesTrackSwipe: services.environment.hasTrackpad && isPlaying)
        run.jump(to: index)
        tip.presenter.onAction = { [weak self] in self?.stop() }
        observer = services.notch.addEventObserver { [weak self] event in self?.handle(event) }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.render() }                           // queue: .main
        }
        // The shape, the notch's visibility, the theme and the settings the sentence uses: the bubble follows them all.
        surroundings = observe({ [weak self] in self?.presentation() }) { [weak self] _ in self?.render() }
        log.info("tutorial started at step \(self.run.number, privacy: .public) of \(self.run.count, privacy: .public)")
        wait(for: run.current)
    }

    private func handle(_ event: NotchEvent) {
        guard isRunning, !run.isFinished else { return }
        if run.handle(event), !isCelebrating {
            celebrate()
        } else {
            // The shell writes the new shape after emitting the event: follow it on the next turn.
            Task { [weak self] in self?.render() }
        }
    }

    /// Shows the step and waits for it (at most `idleLimit`).
    private func wait(for step: TutorialStep?) {
        guard let step else { return finish() }
        showing = .step(step, done: false)
        render()
        announce(content(for: step).text)
        idle?.cancel()
        idle = Task { [weak self, idleLimit] in
            try? await Task.sleep(for: idleLimit)
            guard !Task.isCancelled else { return }
            self?.endIdle()
        }
    }

    private func celebrate() {
        guard case .step(let step, _)? = showing else { return }
        idle?.cancel()
        services.haptics.play(.alignment)
        showing = .step(step, done: true)
        render()
        announce(OnboardingCopy.done)
        log.info("tutorial step \(self.run.number, privacy: .public) done")
        pending = Task { [weak self, celebration] in
            try? await Task.sleep(for: celebration)
            guard !Task.isCancelled else { return }
            self?.advance()
        }
    }

    private func advance() {
        run.advance(isPlaying: isPlaying)
        wait(for: run.current)
    }

    private func finish() {
        services.settings[CoreSettings.tutorialCompleted] = true
        showing = .farewell
        render()
        announce(Self.farewellText)
        log.info("tutorial completed")
        pending = Task { [weak self, farewell] in
            try? await Task.sleep(for: farewell)
            guard !Task.isCancelled else { return }
            self?.stop()
        }
    }

    /// A step waited too long: the tour ends quietly and says where to replay it.
    private func endIdle() {
        guard isRunning else { return }
        log.info("tutorial ended: step \(self.run.number, privacy: .public) waited too long")
        stop()
        announce(String(localized: "The tour ended. Replay it any time from the menu bar.", bundle: .module,
                        comment: "Tutorial: VoiceOver announcement when a step waited for minutes and the tour ended by itself"))
    }

    /// The bubble as it should be now (observed).
    private func presentation() -> TipPresentation {
        TipPresentation(content: isRunning ? showing.map(content(for:)) : nil, surroundings: TipSurroundings(services: services))
    }

    /// Shows what the bubble says now under the shape, or hides it while the notch does not show.
    private func render() {
        tip.render(presentation())
    }

    private func announce(_ text: String) {
        AccessibilityNotification.Announcement(text).post()
    }

    // MARK: Copy

    /// "Skip tour": the bubble's button and the ⌘K command.
    static var skipTitle: String {
        String(localized: "Skip tour", bundle: .module, comment: "Tutorial: always-visible button that ends the tour; also its ⌘K command while it runs")
    }

    private static var farewellText: String {
        String(localized: "That’s the tour. Replay it any time from the menu bar.", bundle: .module,
               comment: "Tutorial: last bubble after every step is done")
    }

    private func content(for showing: Showing) -> TipContent {
        switch showing {
        case .step(let step, let done):
            var content = content(for: step)
            if done { content.mark = .done }
            return content
        case .farewell:
            return TipContent(text: Self.farewellText, mark: .done, actionTitle: OnboardingCopy.done)
        }
    }

    func content(for step: TutorialStep) -> TipContent {
        let progress = String(localized: "\(run.number) of \(run.count)", bundle: .module,
                              comment: "Tutorial: progress in the bubble, e.g. \"2 of 5\" (shown in small capitals)")
        let skip = Self.skipTitle
        switch step {
        case .reachNotch:
            let shortcut = ShortcutText.openCranny(services.settings[CoreSettings.shortcuts])
            let prompt = OpenPrompt(OpenMethod(mode: services.settings[CoreSettings.openMode]), hasShortcut: shortcut != nil)
            return TipContent(text: prompt.tutorialText, keys: prompt.endsWithKeyCap ? shortcut : nil, progress: progress,
                              mark: .symbol(prompt.tutorialSymbol), actionTitle: skip)
        case .dropFile:
            return TipContent(text: String(localized: "Drag any file onto the notch", bundle: .module, comment: "Tutorial step 2"),
                              progress: progress, mark: .symbol("tray.and.arrow.down.fill"), actionTitle: skip)
        case .swipeTrack:
            return TipContent(text: String(localized: "Swipe sideways with two fingers to change the track", bundle: .module, comment: "Tutorial step 3"),
                              progress: progress, mark: .symbol("hand.draw.fill"), actionTitle: skip)
        case .holdCommand:
            return TipContent(text: String(localized: "Hold ⌘ to see every shortcut", bundle: .module, comment: "Tutorial step 4; ⌘ is the Command key"),
                              keys: "⌘", progress: progress, mark: .symbol("keyboard"), actionTitle: skip)
        case .pinAndClose:
            return TipContent(text: String(localized: "Pin it with the pin button, then press Esc", bundle: .module, comment: "Tutorial step 5; followed by the Esc key cap"),
                              keys: "esc", progress: progress, mark: .symbol("pin.fill"), actionTitle: skip)
        }
    }
}
