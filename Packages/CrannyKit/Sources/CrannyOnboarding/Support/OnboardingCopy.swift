// CrannyOnboarding/Support/OnboardingCopy.swift — strings used by more than one onboarding surface, so each
// key has exactly one translator comment (ARCHITECTURE.md §8.7 rule 3).
import Foundation

enum OnboardingCopy {
    /// "Done": the last button of the Welcome window and of the tour, and the VoiceOver word for a finished step.
    static var done: String {
        String(localized: "Done", bundle: .module,
               comment: "Welcome and tutorial: closing button; also VoiceOver's word for a completed step")
    }

    /// "Skip setup": the first step's button and the confirming button of the Esc question.
    static var skipSetup: String {
        String(localized: "Skip setup", bundle: .module,
               comment: "Welcome: skips the whole setup (button on the first step and in the Esc confirmation)")
    }
}
