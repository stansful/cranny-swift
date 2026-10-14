// CrannyOnboarding/WelcomeView.swift — the Welcome window's content (DESIGN.md §12.1): the preview stage on
// top, the step's copy and controls below on the system background, progress dots and buttons at the bottom.
// ↩ continues, ⌘[ goes back, Esc asks "Skip setup?". Hosted by the shell's `WelcomeWindowController`.
import CrannyCore
import CrannyNotchUI
import Foundation
import SwiftUI

/// The Welcome window's content (DESIGN.md §12.1); hosted by the shell's `WelcomeWindowController`.
public struct WelcomeView: View {
    /// 640 × 480 (DESIGN.md §12.1); the window is not resizable.
    public static let windowSize = WelcomeMetrics.window

    /// The window's title (hidden in the title bar; read by VoiceOver and Mission Control).
    public static var windowTitle: String {
        String(localized: "Welcome to Cranny", bundle: .module, comment: "Welcome: window title (VoiceOver, Mission Control)")
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var flow: WelcomeFlow
    @State private var isVisible = true

    /// `onFinish` runs when the person finishes or skips the welcome (the window closes). "Take the tour"
    /// starts the tutorial through `AppControl.startTutorial()`.
    public init(registry: ModuleRegistry, onFinish: @escaping @MainActor () -> Void) {
        self.init(registry: registry, initialStep: .hello) { outcome in
            if outcome == .tour { registry.services.app.startTutorial() }
            onFinish()
        }
    }

    /// Starts at `initialStep` (Settings ▸ About "Show welcome" starts at the beginning; visual QA anywhere)
    /// and reports how it ended; the owner closes the window and acts on `.tour`.
    public init(registry: ModuleRegistry, initialStep: WelcomeStep = .hello,
                onFinish: @escaping @MainActor (WelcomeOutcome) -> Void) {
        let stage = StageScene.live(registry: registry, greeting: WelcomeFlow.greeting)
        _flow = State(initialValue: WelcomeFlow(registry: registry, permissions: registry.services.permissions,
                                                coach: TipPanelPresenter(), stage: stage, initialStep: initialStep,
                                                onFinish: onFinish))
    }

    /// Previews and tests: a prepared flow.
    init(flow: WelcomeFlow) {
        _flow = State(initialValue: flow)
    }

    public var body: some View {
        VStack(spacing: 0) {
            OnboardingStage(stage: flow.stage, registry: flow.registry, onScroll: scrollHandler)
            Divider()
            WelcomeLowerHalf(flow: flow)
        }
        .animation(CrannyMotion.animation(.resize, reduceMotion: reduceMotion), value: flow.stage.height)
        .frame(width: WelcomeMetrics.window.width, height: WelcomeMetrics.window.height)
        .background(.background)
        .background(WindowObserver(isVisible: $isVisible, onClose: stopFlow))
        .background { EscapeKey(flow: flow) }
        .ignoresSafeArea()
        .modifier(SkipConfirmation(flow: flow))
        .onChange(of: isVisible, initial: true) { _, visible in flow.setWindowVisible(visible) }
        .onAppear { flow.start(reduceMotion: reduceMotion) }
        .onDisappear { flow.stop() }
    }

    /// Step 3 practises on the stage; other steps leave scrolls alone.
    private var scrollHandler: (@MainActor (ScrollSample) -> Void)? {
        guard flow.step == .gestures else { return nil }
        let flow = flow
        return { sample in flow.handleScroll(sample) }
    }

    private func stopFlow() { flow.stop() }
}

/// The step's copy and controls (sliding the way you go), then the footer.
private struct WelcomeLowerHalf: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let flow: WelcomeFlow

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            StepPage(flow: flow)
                .id(flow.step)
                .transition(.crannyTab(forward: flow.movedForward, reduceMotion: reduceMotion))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            WelcomeFooter(flow: flow)
        }
        .padding(.horizontal, WelcomeMetrics.inset)
        .padding(.top, Space.xxl)
        .padding(.bottom, Space.xl)
        .animation(CrannyMotion.animation(.contentSwap, reduceMotion: reduceMotion), value: flow.step)
        .clipped()
    }
}

/// Esc anywhere in the window asks first (DESIGN.md §12.1).
private struct EscapeKey: View {
    let flow: WelcomeFlow

    var body: some View {
        Button { flow.requestSkip() } label: { EmptyView() }
            .keyboardShortcut(.cancelAction)
            .opacity(0)
            .accessibilityHidden(true)
    }
}

/// "Skip setup?" — the only way out that asks.
private struct SkipConfirmation: ViewModifier {
    @Bindable var flow: WelcomeFlow

    func body(content: Content) -> some View {
        content.alert(Text("Skip setup?", bundle: .module, comment: "Welcome: Esc confirmation title"),
                      isPresented: $flow.isConfirmingSkip) {
            Button(role: .cancel) {} label: {
                Text("Keep going", bundle: .module, comment: "Welcome: Esc confirmation, stays in the setup")
            }
            Button { flow.finish(.skipped) } label: {
                Text(verbatim: OnboardingCopy.skipSetup)
            }
        } message: {
            Text("You can run it again from Settings ▸ About.", bundle: .module, comment: "Welcome: Esc confirmation message")
        }
    }
}

/// The copy and controls of the current step.
private struct StepPage: View {
    let flow: WelcomeFlow

    var body: some View {
        switch flow.step {
        case .hello: HelloStep(flow: flow)
        case .openIt: OpenItStep(flow: flow)
        case .gestures: GesturesStep(flow: flow)
        case .preset: PresetStep(flow: flow)
        case .permissions: PermissionsStep(flow: flow)
        case .done: DoneStep(flow: flow)
        }
    }
}

#Preview("Welcome · step 1") {
    WelcomePreview(step: .hello)
}
