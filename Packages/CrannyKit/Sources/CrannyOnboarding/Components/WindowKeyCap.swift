// CrannyOnboarding/Components/WindowKeyCap.swift — a key cap for the Welcome window's lower half. Core's
// `KeyCap` is drawn for the always-dark notch; this one uses system colours so it reads in Light and Dark
// (DESIGN.md §2.0 "two worlds"), with the same geometry (Radius.keycap, rounded semibold glyphs).
import CrannyCore
import SwiftUI

struct WindowKeyCap: View {
    @Environment(\.displayScale) private var displayScale
    let keys: String

    init(_ keys: String) { self.keys = keys }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.keycap, style: .continuous)
        Text(verbatim: keys)
            .font(.system(.callout, design: .rounded).weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, Space.s)
            .frame(minWidth: Space.xxl + Space.xs, minHeight: Space.xxl + Space.xs)
            .background(shape.fill(.quaternary.opacity(0.6)))
            .overlay(shape.strokeBorder(.separator, lineWidth: StrokeWidth.hairline(displayScale) * 2))
            .fixedSize()
            .accessibilityHidden(true)       // the surrounding text names the shortcut
    }
}

#Preview("Window key caps") {
    HStack(spacing: Space.m) {
        WindowKeyCap("⌃⌥N")
        WindowKeyCap("⌘")
        WindowKeyCap("esc")
    }
    .padding(Space.xxl)
}
