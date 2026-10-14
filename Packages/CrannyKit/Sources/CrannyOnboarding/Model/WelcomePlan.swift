// CrannyOnboarding/Model/WelcomePlan.swift — which steps the Welcome window shows, and in what order (pure).
import Foundation

/// The visible steps for this Mac: all six, minus the gesture step without a trackpad (DESIGN.md §12.1).
/// Numbers are 1-based, as VoiceOver reads them ("Step 2 of 6").
nonisolated struct WelcomePlan: Equatable, Sendable {
    let steps: [WelcomeStep]

    init(hasTrackpad: Bool) {
        steps = WelcomeStep.allCases.filter { $0 != .gestures || hasTrackpad }
    }

    var count: Int { steps.count }
    var first: WelcomeStep { steps.first ?? .hello }
    var last: WelcomeStep { steps.last ?? .done }

    /// 1-based position of a visible step (a hidden step reports the position of the step that replaces it).
    func number(of step: WelcomeStep) -> Int {
        (steps.firstIndex(of: resolve(step)) ?? 0) + 1
    }

    func next(after step: WelcomeStep) -> WelcomeStep? {
        guard let index = steps.firstIndex(of: resolve(step)), index + 1 < steps.count else { return nil }
        return steps[index + 1]
    }

    func previous(before step: WelcomeStep) -> WelcomeStep? {
        guard let index = steps.firstIndex(of: resolve(step)), index > 0 else { return nil }
        return steps[index - 1]
    }

    /// The step to show for a requested one: a hidden step falls through to the next visible step.
    func resolve(_ step: WelcomeStep) -> WelcomeStep {
        if steps.contains(step) { return step }
        let later = WelcomeStep.allCases.drop { $0 != step }
        return later.first(where: steps.contains) ?? last
    }
}
