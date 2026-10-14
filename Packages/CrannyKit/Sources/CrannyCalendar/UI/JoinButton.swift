// CrannyCalendar/UI/JoinButton.swift — Join, always green (`success`) with a black `person.2.wave.2.fill`
// (DESIGN.md §0.3 #15, §9.2): a 34 × 20 pill in the band, a capsule with the glyph AND "Join" in the peek and the
// widget (never colour or glyph alone, §16; a widget row too narrow for the word keeps the glyph and the
// VoiceOver label). The hit area is padded beyond the pill (≥ 32 × 24 in the band, ≥ 28 × 24 in the Nook).
import CrannyCore
import Foundation
import SwiftUI

struct JoinButton: View {
    enum Size {
        /// The band: glyph-only pill, 34 × 20 (× notch unit).
        case band
        /// Widget rows: 22-pt capsule; `word: false` when the row is too narrow (the row decides, see `EventRow`).
        case row(word: Bool)
        /// Peek rows: 28-pt prominent capsule.
        case peek
    }

    let size: Size
    let action: @MainActor () -> Void

    var body: some View {
        Button(action: action) {
            switch size {
            case .band, .row(word: false):
                JoinGlyph()
            case .row(word: true), .peek:
                HStack(spacing: Space.xs) { JoinGlyph(); JoinWord() }
            }
        }
        .buttonStyle(JoinButtonStyle(size: size))
        .accessibilityLabel(Text("Join meeting", bundle: .module, comment: "Calendar: Join button, VoiceOver label"))
        .help(String(localized: "Join meeting", bundle: .module, comment: "Calendar: Join button, VoiceOver label"))
    }
}

private struct JoinGlyph: View {
    var body: some View { Image(systemName: "person.2.wave.2.fill").accessibilityHidden(true) }
}

private struct JoinWord: View {
    var body: some View {
        Text("Join", bundle: .module, comment: "Calendar: Join button title (opens the meeting link)").lineLimit(1)
    }
}

private struct JoinButtonStyle: ButtonStyle {
    let size: JoinButton.Size
    func makeBody(configuration: Configuration) -> some View { JoinBody(configuration: configuration, size: size) }

    struct JoinBody: View {
        @Environment(\.cranny) private var theme
        @Environment(\.isEnabled) private var enabled
        @State private var hovered = false
        let configuration: Configuration
        let size: JoinButton.Size

        var body: some View {
            let u = theme.notchUnit
            let isBand = if case .band = size { true } else { false }
            let height: CGFloat = switch size { case .band: 20 * u; case .row: 22; case .peek: HitTarget.preferred }
            let hit: CGSize = isBand ? CGSize(width: 34 * u, height: HitTarget.band.height * u) : HitTarget.nook
            // `success` (= palette.success) and the label colour Core derives for a filled accent: black.
            let fill = SemanticColor.success.rgb(theme.palette.variant == .highContrast)
            configuration.label
                .font(labelFont(u))
                .foregroundStyle(fill.onColor.color)
                .padding(.horizontal, isBand ? 0 : Space.m)
                .frame(minWidth: isBand ? 34 * u : height, minHeight: height, maxHeight: height)
                .background(Capsule(style: .continuous).fill(fill.color))
                .overlay(Capsule(style: .continuous).fill(hovered && !configuration.isPressed ? theme.palette.controlHover : .clear))
                .fixedSize()
                .frame(minWidth: hit.width, minHeight: hit.height)
                // Never narrower than the pill: a min-only frame accepts a smaller proposal, so a row's HStack
                // would squeeze the hit area and the pill would spill past the card (Russian "Подключиться").
                .fixedSize()
                .contentShape(Rectangle())
                .scaleEffect(configuration.isPressed && !theme.reduceMotion ? 0.94 : 1)
                .opacity(enabled ? (configuration.isPressed && theme.reduceMotion ? 0.7 : 1) : 0.4)
                .onHover { hovered = $0 }
                .animation(theme.animation(.hover), value: hovered)
                .animation(theme.animation(.press), value: configuration.isPressed)
        }

        private func labelFont(_ u: CGFloat) -> Font {
            switch size {
            // Band symbols: semibold 13 pt × notch unit (DESIGN.md §14.1), the `compact` size.
            case .band: CrannyTextStyle.compact.font(notchUnit: u)
            case .row: CrannyTextStyle.caption.font(textSize: theme.textSize).weight(.semibold)
            case .peek: CrannyTextStyle.headline.font(textSize: theme.textSize)
            }
        }
    }
}

#Preview("Join · band, row, peek") {
    VStack(spacing: Space.l) {
        JoinButton(size: .band) {}
        JoinButton(size: .row(word: true)) {}
        JoinButton(size: .row(word: false)) {}
        JoinButton(size: .peek) {}
    }
    .padding()
    .background(.black)
    .crannyThemeRoot(CrannyTheme())
}
