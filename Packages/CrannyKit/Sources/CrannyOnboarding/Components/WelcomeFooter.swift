// CrannyOnboarding/Components/WelcomeFooter.swift — progress dots and the step's buttons (DESIGN.md §12.1):
// ↩ continues, ⌘[ goes back. Steps 2 and 3 enable Continue once they were really done and offer "Skip" until
// then (every step can be skipped); step 1 offers "Skip setup", the last step "Done" and "Take the 1-minute tour".
import CrannyCore
import Foundation
import SwiftUI

struct WelcomeFooter: View {
    let flow: WelcomeFlow

    var body: some View {
        HStack(spacing: Space.m) {
            ProgressDots(current: flow.stepNumber, count: flow.stepCount)
            Spacer(minLength: Space.l)
            if flow.canGoBack {
                Button { flow.goBack() } label: {
                    Text("Back", bundle: .module, comment: "Welcome: button that returns to the previous step (⌘[)")
                }
                .keyboardShortcut("[", modifiers: .command)
            } else {
                Button { flow.requestSkip() } label: {
                    Text(verbatim: OnboardingCopy.skipSetup)
                }
            }
            if flow.isLastStep {
                Button { flow.finish(.done) } label: { Text(verbatim: OnboardingCopy.done) }
                Button { flow.finish(.tour) } label: {
                    Text("Take the 1-minute tour", bundle: .module, comment: "Welcome step 6: primary button that starts the interactive tutorial")
                }
                .keyboardShortcut(.defaultAction)
            } else {
                if flow.offersSkip {
                    Button { flow.goForward() } label: {
                        Text("Skip", bundle: .module, comment: "Welcome: skips a step that was not tried yet")
                    }
                }
                Button { flow.goForward() } label: {
                    Text("Continue", bundle: .module, comment: "Welcome: button that goes to the next step (↩)")
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!flow.canContinue)
            }
        }
        .controlSize(.large)
    }
}
