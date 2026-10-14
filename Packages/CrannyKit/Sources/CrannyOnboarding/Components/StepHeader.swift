// CrannyOnboarding/Components/StepHeader.swift — a step's headline and one sentence, in system text styles
// (DESIGN.md §2.2: Settings and onboarding use system styles). The headline is a VoiceOver header and takes
// accessibility focus when the step changes, so VoiceOver starts reading the new step.
import CrannyCore
import SwiftUI

struct StepHeader: View {
    @AccessibilityFocusState private var isFocused: Bool
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
        .accessibilityFocused($isFocused)
        .onAppear { isFocused = true }          // a new step: VoiceOver starts reading it from the top
    }
}

#Preview("Step header") {
    StepHeader(title: "Look up. That's Cranny.",
               message: "Your music, calendar, files and shortcuts live in the notch, one glance away.")
        .padding(WelcomeMetrics.inset)
        .frame(width: WelcomeMetrics.window.width)
}
