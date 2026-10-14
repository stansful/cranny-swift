// CrannyOnboarding/Components/CheckBadge.swift — the ✓ of a step that was really done (green, `.bounce` once,
// DESIGN.md §12.1 and §14.1: symbols animate only on a state change, never under Reduce Motion). Before that,
// an empty circle; colour is never the only cue (the glyph changes too). The window is a system-world surface,
// so the green is the system's (it adapts to Light/Dark and Increase Contrast).
import CrannyCore
import SwiftUI

struct CheckBadge: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let isDone: Bool
    var size: CGFloat = Space.xl

    var body: some View {
        Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
            .font(.system(size: size, weight: .medium))
            .foregroundStyle(isDone ? AnyShapeStyle(Color.green) : AnyShapeStyle(.tertiary))
            .contentTransition(.symbolEffect(.replace))
            // The bounce plays when the value changes; under Reduce Motion the value never changes.
            .symbolEffect(.bounce, value: isDone && !reduceMotion)
            .accessibilityHidden(true)
    }
}

#Preview("Check badge") {
    HStack(spacing: Space.xl) {
        CheckBadge(isDone: false)
        CheckBadge(isDone: true)
    }
    .padding(Space.xxl)
}
