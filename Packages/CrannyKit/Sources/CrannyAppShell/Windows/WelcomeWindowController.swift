// CrannyAppShell/Windows/WelcomeWindowController.swift — the Welcome window (ARCHITECTURE.md §5.9), WP15.
// 640 × 480, full-size content, hidden title bar, not resizable, centred, hosting `WelcomeView`. Shown on first
// launch (`onboardingCompletedVersion == nil`, from a launch hook once every module has started) and from
// "Show welcome". It also owns the app's one `TutorialController`: "Take the 1-minute tour" starts it here, and
// `AppControl.startTutorial()` (menu bar, Settings ▸ About) reaches it through `startTutorial()`.
import AppKit
import CrannyCore
import CrannyOnboarding
import Foundation
import os
import SwiftUI

private let log = Log.logger(.onboarding)

@MainActor final class WelcomeWindowController: NSObject, NSWindowDelegate {
    /// The interactive tutorial in the real notch (DESIGN.md §12.2), one per app.
    let tutorial: TutorialController

    private let registry: ModuleRegistry
    private var window: NSWindow?
    /// Set once the welcome reported how it ended (a close before that counts as "skipped").
    private var hasFinished = false
    /// The app that was frontmost before the window opened gets activation back when it closes.
    private var previousApp: NSRunningApplication?
    /// Visual QA runs (`--qa-*`) record nothing: the defaults domain is shared by every local build.
    private var isVisualQA = false

    init(registry: ModuleRegistry) {
        self.registry = registry
        tutorial = TutorialController(registry: registry)
        super.init()
        // After every module's launch hook, so the first-launch welcome shows a fully started app.
        registry.onLaunch { [weak self] in self?.applicationDidLaunch() }
    }

    /// Opens (or brings forward) the welcome at its first step. Call in response to a user action or at first launch.
    func show() { show(at: .hello) }

    /// Starts the tutorial (`AppControl.startTutorial()`); an open welcome closes first (as if skipped).
    func startTutorial() {
        window?.close()
        tutorial.start()
    }

    // MARK: Private

    private func show(at step: WelcomeStep) {
        if let window {
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
            return
        }
        let front = NSWorkspace.shared.frontmostApplication
        previousApp = front?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? nil : front
        hasFinished = false
        let view = WelcomeView(registry: registry, initialStep: step) { [weak self] outcome in self?.finish(outcome) }
        let host = NSHostingController(rootView: view)
        host.sizingOptions = []
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: WelcomeView.windowSize),
                              styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        window.contentViewController = host
        window.setContentSize(WelcomeView.windowSize)
        window.title = WelcomeView.windowTitle
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.isMovableByWindowBackground = true
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenNone]
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        self.window = window
        if isVisualQA {
            window.orderFrontRegardless()         // screenshots only: never take focus from whoever uses the Mac
        } else {
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
        }
        log.info("welcome shown at \(step.rawValue, privacy: .public)")
    }

    /// The welcome ended (Done, tour or Skip setup): close, then act.
    private func finish(_ outcome: WelcomeOutcome) {
        hasFinished = true
        window?.close()
        if outcome == .tour { tutorial.start() }
    }

    func windowWillClose(_ notification: Notification) {
        // The close button before the end counts as "Skip setup": the welcome is not forced on the next launch and
        // stays available from Settings ▸ About.
        if !hasFinished, !isVisualQA {
            registry.services.settings[CoreSettings.onboardingCompletedVersion] = AppInfo.current().version
        }
        window = nil
        // Cooperative activation hand-back (ARCHITECTURE.md §5.9, as for Settings).
        if let previousApp, !previousApp.isTerminated { previousApp.activate() }
        previousApp = nil
    }

    private func applicationDidLaunch() {
        #if DEBUG
        let qa = QAHooks.Options(arguments: CommandLine.arguments)
        isVisualQA = !qa.isEmpty
        if let name = qa.welcomeStep {
            show(at: WelcomeStep(rawValue: name) ?? .hello)
            return
        }
        if let step = qa.tutorialStep {
            tutorial.startForVisualQA(atStep: step)
            return
        }
        if isVisualQA { return }                  // QA screenshots never get the first-launch welcome on top
        #endif
        if registry.services.settings[CoreSettings.onboardingCompletedVersion] == nil { show() }
    }
}
