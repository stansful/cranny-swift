// CrannyAppShell/Windows/WelcomeWindowController.swift — the Welcome window (ARCHITECTURE.md §5.9).
// 640 × 480, full-size content, hidden title bar, not resizable, centred, hosting `WelcomeView`. Shown on first
// launch (`onboardingCompletedVersion == nil`, from a launch hook once every module has started) and from
// "Show welcome". "Take the 1-minute tutorial" closes the window and asks `AppControl.startTutorial()`, so the app keeps
// one `TutorialController` (the app services own it) for the welcome, the menu bar and Settings ▸ About.
// The controller's decisions are pure (`WelcomeWindowPolicy`) and tested without windows.
import AppKit
import CrannyCore
import CrannyOnboarding
import Foundation
import os
import SwiftUI

private let log = Log.logger(.onboarding)

@MainActor final class WelcomeWindowController: NSObject, NSWindowDelegate {
    private let registry: ModuleRegistry
    private var window: NSWindow?
    /// Set once the welcome reported how it ended (a close before that counts as "skipped").
    private var hasFinished = false
    /// The app that was frontmost before the window opened gets activation back when it closes.
    private var previousApp: NSRunningApplication?
    /// Visual QA runs (`--qa-*`) record nothing: the defaults domain is shared by every local build.
    private var isVisualQA = false
    #if DEBUG
    /// `--qa-tutorial` only: a tour shown without going through `AppControl`.
    private var visualQATutorial: TutorialController?
    #endif

    init(registry: ModuleRegistry) {
        self.registry = registry
        super.init()
        // After every module's launch hook, so the first-launch welcome shows a fully started app.
        registry.onLaunch { [weak self] in self?.applicationDidLaunch() }
    }

    /// Opens (or brings forward) the welcome at its first step. Call in response to a user action or at first launch.
    func show() { show(at: .hello) }

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
        // The FRAME is 640 x 480 and the SwiftUI content covers all of it, title bar included. A hosting view
        // that IS the window's content view resizes the window to its content plus the hidden title bar on
        // every layout (NSHostingView.windowDidLayout; 32 pt on macOS 27, even with no sizing options), so it
        // sits inside a plain container instead.
        let host = NSHostingView(rootView: view)
        host.sizingOptions = []
        let container = NSView(frame: CGRect(origin: .zero, size: WelcomeView.windowSize))
        host.frame = container.bounds
        host.autoresizingMask = [.width, .height]
        container.addSubview(host)
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: WelcomeView.windowSize),
                              styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        window.contentView = container
        window.setFrame(CGRect(origin: window.frame.origin, size: WelcomeView.windowSize), display: false)
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
        log.info("welcome shown at \(step.rawValue, privacy: .public), frame \(NSStringFromRect(window.frame), privacy: .public)")
    }

    /// The welcome ended (Done, tour or Skip setup): close, then act.
    private func finish(_ outcome: WelcomeOutcome) {
        hasFinished = true
        window?.close()
        if outcome == .tour { registry.services.app.startTutorial() }
    }

    func windowWillClose(_ notification: Notification) {
        // The close button before the end counts as "Skip setup": the welcome is not forced on the next launch and
        // stays available from Settings ▸ About.
        if WelcomeWindowPolicy.recordsCompletionOnClose(hasFinished: hasFinished, isVisualQA: isVisualQA) {
            registry.services.settings[CoreSettings.onboardingCompletedVersion] = AppInfo.current().version
        }
        window = nil
        // Cooperative activation hand-back (ARCHITECTURE.md §5.9), only while Cranny is still the active app: a
        // close button clicked from another app, or a welcome that ends after the person moved on, takes nothing.
        if let previousApp,
           WelcomeWindowPolicy.handsBackActivation(isActive: NSApp.isActive, previousAppIsRunning: !previousApp.isTerminated) {
            NSApp.yieldActivation(to: previousApp)
            previousApp.activate(from: .current, options: [])
        }
        previousApp = nil
    }

    private func applicationDidLaunch() {
        #if DEBUG
        let qa = QAHooks.Options(arguments: CommandLine.arguments)
        isVisualQA = !qa.isEmpty
        OnboardingVisualQA.showsTipsAnyway = qa.welcomeStep != nil || qa.tutorialStep != nil
        let launch = WelcomeWindowPolicy.launch(completedVersion: registry.services.settings[CoreSettings.onboardingCompletedVersion],
                                                qaWelcomeStep: qa.welcomeStep, qaTutorialStep: qa.tutorialStep,
                                                isVisualQA: isVisualQA)
        #else
        let launch = WelcomeWindowPolicy.launch(completedVersion: registry.services.settings[CoreSettings.onboardingCompletedVersion],
                                                qaWelcomeStep: nil, qaTutorialStep: nil, isVisualQA: false)
        #endif
        switch launch {
        case .nothing:
            return
        case .welcome(let step):
            show(at: step)
        case .tutorial(let step):
            #if DEBUG
            let tutorial = TutorialController(registry: registry)
            visualQATutorial = tutorial
            tutorial.startForVisualQA(atStep: step)
            #else
            _ = step
            #endif
        }
        #if DEBUG
        if let directory = qa.snapshotDirectory { snapshotForVisualQA(into: directory) }
        #endif
    }

    #if DEBUG
    /// Visual QA: draws every visible window of the app (welcome, tip, notch panel) into `<directory>/<level>-<n>.png`
    /// once the step has settled. In-process, so it also works while the screen is locked (window-server captures
    /// fail then); materials and Metal effects may draw flat.
    private func snapshotForVisualQA(into directory: URL) {
        Task { [registry] in
            try? await Task.sleep(for: .seconds(3))
            let shape = registry.services.notch.shapeFrameOnScreen().map(NSStringFromRect) ?? "none"
            var frames = "shape \(shape)\n"
            for (index, window) in NSApp.windows.enumerated() where window.isVisible {
                frames += "\(window.level.rawValue)-\(index) frame \(NSStringFromRect(window.frame)) content \(NSStringFromRect(window.contentView?.bounds ?? .zero))\n"
                guard let view = window.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
                view.cacheDisplay(in: view.bounds, to: rep)
                let url = directory.appendingPathComponent("\(window.level.rawValue)-\(index).png")
                do {
                    try rep.representation(using: .png, properties: [:])?.write(to: url)
                    log.info("QA: snapshot \(url.lastPathComponent, privacy: .public) \(NSStringFromRect(window.frame), privacy: .public)")
                } catch {
                    log.error("QA: snapshot failed: \(error.localizedDescription, privacy: .public)")
                }
            }
            try? frames.write(to: directory.appendingPathComponent("frames.txt"), atomically: true, encoding: .utf8)
        }
    }
    #endif
}

/// `WelcomeWindowController`'s decisions (pure, tested in CrannyAppShellTests).
enum WelcomeWindowPolicy {
    /// What launch opens.
    enum Launch: Equatable {
        case nothing
        /// The welcome at a step: the first launch (`.hello`), or a visual QA step.
        case welcome(WelcomeStep)
        /// Visual QA only: the tour at a 1-based step.
        case tutorial(step: Int)
    }

    /// The welcome shows on first launch only (`onboardingCompletedVersion == nil`). Visual QA runs (`--qa-*`) show
    /// exactly what they ask for and never get the first-launch welcome on top. An unknown QA step name shows step 1.
    static func launch(completedVersion: String?, qaWelcomeStep: String?, qaTutorialStep: Int?, isVisualQA: Bool) -> Launch {
        if let qaWelcomeStep { return .welcome(WelcomeStep(rawValue: qaWelcomeStep) ?? .hello) }
        if let qaTutorialStep { return .tutorial(step: qaTutorialStep) }
        if isVisualQA { return .nothing }
        return completedVersion == nil ? .welcome(.hello) : .nothing
    }

    /// A close before the welcome reported how it ended (the close button) counts as "Skip setup" and records
    /// completion; visual QA records nothing (every local build shares the defaults domain).
    static func recordsCompletionOnClose(hasFinished: Bool, isVisualQA: Bool) -> Bool {
        !hasFinished && !isVisualQA
    }

    /// Activation goes back to the app that was in front only while Cranny is still active (never steal focus).
    static func handsBackActivation(isActive: Bool, previousAppIsRunning: Bool) -> Bool {
        isActive && previousAppIsRunning
    }
}
