// CrannyOnboarding/Components/StepHeader.swift — a step's headline and one sentence, in system text styles
// (DESIGN.md §2.2: Settings and onboarding use system styles). The headline is a VoiceOver header and takes
// accessibility focus when the step changes, so VoiceOver starts reading the new step.
import CrannyCore
import SwiftUI

struct StepHeader: View {
    @Environment(\.isStaticSnapshot) private var isStaticSnapshot
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(verbatim: title)
                .font(.title2.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            Text(verbatim: message)
                .font(.body)
                .foregroundStyle(.secondary)
                .lineLimit(2, reservesSpace: false)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .modifier(FocusOnAppear(isEnabled: !isStaticSnapshot))
    }
}

/// A new step: VoiceOver starts reading it from the top.
private struct FocusOnAppear: ViewModifier {
    @AccessibilityFocusState private var isFocused: Bool
    let isEnabled: Bool

    @ViewBuilder func body(content: Content) -> some View {
        if isEnabled {
            content.accessibilityFocused($isFocused).onAppear { isFocused = true }
        } else {
            content
        }
    }
}

extension EnvironmentValues {
    /// Rendered with `ImageRenderer` (render tests): skip what it cannot draw, such as accessibility focus state.
    @Entry var isStaticSnapshot = false
}

#Preview("Step header") {
    StepHeader(title: "Look up. That's Cranny.",
               message: "Your music, calendar, files and shortcuts live in the notch, one glance away.")
        .padding(WelcomeMetrics.inset)
        .frame(width: WelcomeMetrics.window.width)
}
