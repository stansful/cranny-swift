// CrannyOnboarding/WelcomeView.swift — the Welcome window content (DESIGN.md §12.1), WP15.
// WP0 skeleton: the stage (a dark desktop with the brand aurora) over the first step's copy. WP15 adds the six
// steps with real detection, the onboarding stage built with ThemeResolver and the presets.
import CrannyCore
import CrannyEffects
import CrannyNotchUI
import SwiftUI

/// The Welcome window's content (DESIGN.md §12.1); hosted by the shell's `WelcomeWindowController`.
public struct WelcomeView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let registry: ModuleRegistry
    private let onFinish: @MainActor () -> Void

    /// `onFinish` runs when the person finishes or skips the welcome (the window closes).
    public init(registry: ModuleRegistry, onFinish: @escaping @MainActor () -> Void) {
        self.registry = registry; self.onFinish = onFinish
    }

    public var body: some View {
        VStack(spacing: 0) {
            AuroraField(palette: .afterglow, level: .subtle, energy: 0,
                        budget: EffectBudget(isOpen: true, onScreen: true, lowPower: false, fullScreenFront: false,
                                             reduceMotion: reduceMotion, onBattery: false))
                .frame(height: 240)
                .frame(maxWidth: .infinity)
                .background(Color.black)
            VStack(spacing: 12) {
                Text("Look up. That's Cranny.", bundle: .module, comment: "Welcome headline")
                    .font(.title.weight(.semibold))
                Text("Your music, calendar, files and shortcuts live in the notch, one glance away.",
                     bundle: .module, comment: "Welcome: one sentence about what Cranny does")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Spacer(minLength: 0)
                Button { onFinish() } label: { Text("Continue", bundle: .module, comment: "Onboarding button") }
                    .keyboardShortcut(.defaultAction)
                    .controlSize(.large)
            }
            .padding(32)
        }
        .frame(width: 640, height: 480)
    }
}

#Preview("Welcome") {
    WelcomeView(registry: ModuleRegistry(services: .preview())) {}
        .background(.black)
        .preferredColorScheme(.dark)
        .crannyThemeRoot(CrannyTheme())
}
