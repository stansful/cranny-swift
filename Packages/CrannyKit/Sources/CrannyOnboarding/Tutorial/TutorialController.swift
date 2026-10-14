// CrannyOnboarding/Tutorial/TutorialController.swift — the 5-step interactive tutorial in the real notch
// (DESIGN.md §12.2). Intra-shell interface fixed by WP0 (ARCHITECTURE.md §10.0): `init(registry:)`, `start()`,
// `stop()`, `isRunning`. Every step completes on real detection through `NotchControl.addEventObserver`, with a
// ✓ bounce, an `.alignment` haptic and a VoiceOver announcement; the bubble sits under
// `NotchControl.shapeFrameOnScreen()`. Nothing runs between events (no timers, no polling).
import AppKit
import CrannyCore
import Foundation
import os
import SwiftUI

private let log = Log.logger(.onboarding)

/// Runs the interactive tutorial in the real notch (DESIGN.md §12.2); owned by the shell, started from the
/// Welcome window, the menu bar and Settings ▸ About ("Replay tutorial").
@MainActor public final class TutorialController {
    /// True from `start()` until the tour ends, is skipped or `stop()`.
    public private(set) var isRunning = false

    private let registry: ModuleRegistry
    private let presenter: any TipPresenter
    /// How long the ✓ of a finished step stays before the next step.
    private let celebration: Duration
    /// How long the closing bubble stays.
    private let farewell: Duration
    private var run = TutorialRun(includesTrackSwipe: false)
    private var observer: UUID?
    private var screenObserver: (any NSObjectProtocol)?
    private var isCelebrating = false
    private var pending: Task<Void, Never>?

    /// The registry gives the tutorial `NotchControl` (bubble anchor, step detection) and the settings.
    public convenience init(registry: ModuleRegistry) {
        self.init(registry: registry, presenter: TipPanelPresenter())
    }

    init(registry: ModuleRegistry, presenter: any TipPresenter,
         celebration: Duration = .milliseconds(900), farewell: Duration = .seconds(5)) {
        self.registry = registry
        self.presenter = presenter
        self.celebration = celebration
        self.farewell = farewell
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
        if let observer { services.notch.removeEventObserver(observer) }
        observer = nil
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
        presenter.hide()
        isRunning = false
        isCelebrating = false
    }

    // MARK: Run

    private var services: CrannyServices { registry.services }
    private var isPlaying: Bool { services.nowPlaying?.nowPlaying?.isPlaying == true }

    private func begin(at index: Int) {
        stop()
        isRunning = true
        run = TutorialRun(includesTrackSwipe: services.environment.hasTrackpad && isPlaying)
        run.jump(to: index)
        presenter.onAction = { [weak self] in self?.stop() }
        observer = services.notch.addEventObserver { [weak self] event in self?.handle(event) }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.present() }                          // queue: .main
        }
        log.info("tutorial started at step \(self.run.number, privacy: .public) of \(self.run.count, privacy: .public)")
        present()
        announce(content(for: run.current).text)
    }

    private func handle(_ event: NotchEvent) {
        guard isRunning else { return }
        if !isCelebrating, run.handle(event) {
            celebrate()
        } else {
            // The shell writes the new shape after emitting the event: follow it on the next turn.
            Task { [weak self] in self?.present() }
        }
    }

    private func celebrate() {
        isCelebrating = true
        services.haptics.play(.alignment)
        var done = content(for: run.current)
        done.mark = .done
        presenter.show(done, under: services.notch.shapeFrameOnScreen())
        announce(OnboardingCopy.done)
        log.info("tutorial step \(self.run.number, privacy: .public) done")
        pending = Task { [weak self, celebration] in
            try? await Task.sleep(for: celebration)
            guard !Task.isCancelled else { return }
            self?.advance()
        }
    }

    private func advance() {
        isCelebrating = false
        run.advance(isPlaying: isPlaying)
        guard !run.isFinished else { return finish() }
        present()
        announce(content(for: run.current).text)
    }

    private func finish() {
        services.settings[CoreSettings.tutorialCompleted] = true
        let text = String(localized: "That's the tour. Replay it any time from the menu bar.", bundle: .module,
                          comment: "Tutorial: last bubble after every step is done")
        presenter.show(TipContent(text: text, mark: .done,
                                  actionTitle: OnboardingCopy.done),
                       under: services.notch.shapeFrameOnScreen())
        announce(text)
        log.info("tutorial completed")
        pending = Task { [weak self, farewell] in
            try? await Task.sleep(for: farewell)
            guard !Task.isCancelled else { return }
            self?.stop()
        }
    }

    private func present() {
        guard isRunning, !run.isFinished, !isCelebrating else { return }
        presenter.show(content(for: run.current), under: services.notch.shapeFrameOnScreen())
    }

    private func announce(_ text: String) {
        AccessibilityNotification.Announcement(text).post()
    }

    // MARK: Copy

    func content(for step: TutorialStep?) -> TipContent {
        let progress = String(localized: "\(run.number) of \(run.count)", bundle: .module,
                              comment: "Tutorial: progress in the bubble, e.g. \"2 of 5\" (shown in small capitals)")
        let skip = String(localized: "Skip tour", bundle: .module, comment: "Tutorial: always-visible button that ends the tour")
        switch step ?? .reachNotch {
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
