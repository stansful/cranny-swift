// CrannyOnboarding/Components/SelectableCard.swift — the card behind step 2's ways in and step 4's layouts:
// a quiet system fill, an accent ring and wash when selected (plus a ✓ glyph, so colour is not the only cue),
// a press scale that respects Reduce Motion, and a 2-pt focus ring for Full Keyboard Access.
import CrannyCore
import SwiftUI

struct SelectableCardStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        CardBody(configuration: configuration, isSelected: isSelected)
    }

    private struct CardBody: View {
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @Environment(\.isFocused) private var isFocused
        @State private var hovered = false
        let configuration: Configuration
        let isSelected: Bool

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: WelcomeMetrics.cardRadius, style: .continuous)
            configuration.label
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(shape.fill(fill))
                .overlay(shape.strokeBorder(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.separator),
                                            lineWidth: isSelected ? StrokeWidth.focus : StrokeWidth.regular))
                .overlay {
                    if isFocused && !isSelected {
                        shape.inset(by: -Radius.focusRingOutset)
                            .strokeBorder(.tint, lineWidth: StrokeWidth.focus)
                    }
                }
                .contentShape(shape)
                .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
                .onHover { hovered = $0 }
                .animation(CrannyMotion.animation(.hover, reduceMotion: reduceMotion), value: hovered)
                .animation(CrannyMotion.animation(.press, reduceMotion: reduceMotion), value: configuration.isPressed)
                .animation(CrannyMotion.animation(.commit, reduceMotion: reduceMotion), value: isSelected)
        }

        private var fill: AnyShapeStyle {
            if isSelected { return AnyShapeStyle(.tint.opacity(0.08)) }
            return AnyShapeStyle(.quaternary.opacity(hovered ? 0.7 : 0.4))
        }
    }
}

#Preview("Selectable cards") {
    HStack(spacing: Space.m) {
        Button {} label: { Text(verbatim: "Hover").padding(Space.l) }
            .buttonStyle(SelectableCardStyle(isSelected: true))
        Button {} label: { Text(verbatim: "Click").padding(Space.l) }
            .buttonStyle(SelectableCardStyle(isSelected: false))
    }
    .frame(height: 96)
    .padding(Space.xxl)
}
