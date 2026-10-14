// CrannyOnboarding/Stage/StageGreeting.swift — the stage's copy of the real notch's "Hi" (DESIGN.md §12.1
// step 1). The real one is the shell's flash (`NotchControl.flash`); this sample lives only in the stage's
// `sampleActivities`, so it is never registered or arbitrated.
import CrannyCore
import Foundation
import Observation
import SwiftUI

@MainActor @Observable final class StageGreeting: LiveActivity {
    static let activityID: ActivityID = "onboarding.greeting"
    /// `hand.wave.fill`, DESIGN.md §14.1 (Settings, onboarding).
    static let symbol = "hand.wave.fill"

    let id: ActivityID = StageGreeting.activityID
    let isActive = true
    let priority: ActivityPriority = .alert
    let revision = 1
    let label: String

    /// `label` is already localized (it must fit the compact wing, measured like every flash label — `NotchControl.flash`).
    init(label: String) { self.label = label }

    var slot: SlotWidth { label.count <= 4 ? .medium : .wide }
    var accessibilityLabel: String { label }

    func compactLeading() -> some View { GreetingGlyph() }
    func compactTrailing() -> some View { GreetingLabel(label: label, style: .compact) }
    func minimal() -> some View { GreetingGlyph() }
    func peekRow() -> some View {
        HStack(spacing: Space.l) {
            GreetingGlyph()
            GreetingLabel(label: label, style: .title)
            Spacer(minLength: 0)
        }
    }
}

/// The waving hand in the band (semibold, × notch unit, DESIGN.md §14.1 rendering).
private struct GreetingGlyph: View {
    @Environment(\.cranny) private var theme
    var body: some View {
        Image(systemName: StageGreeting.symbol)
            .font(.system(size: CrannyTextStyle.compact.spec.size * theme.notchUnit, weight: .semibold))
            .foregroundStyle(theme.palette.label)
            .accessibilityHidden(true)
    }
}

private struct GreetingLabel: View {
    @Environment(\.cranny) private var theme
    let label: String
    let style: CrannyTextStyle
    var body: some View {
        Text(verbatim: label).crannyFont(style).lineLimit(1).foregroundStyle(theme.palette.label)
    }
}

#Preview("Stage greeting · compact") {
    let greeting = StageGreeting(label: "Hi")
    return HStack(spacing: Space.l) { greeting.compactLeading(); greeting.compactTrailing() }
        .padding(Space.xl)
        .background(.black)
        .crannyThemeRoot(CrannyTheme())
}
