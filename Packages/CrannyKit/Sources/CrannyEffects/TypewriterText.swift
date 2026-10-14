// CrannyEffects/TypewriterText.swift — read-only animated text for CrannyNotchUI and onboarding (tutorial bubble,
// welcome headlines; DESIGN.md §7.5 "Typing effect"): a `TextRenderer` typewriter on macOS 15+, a plain fade on 14.
// Off under Reduce Motion and the Instant personality. VoiceOver always reads the whole text at once.
import CrannyCore
import Foundation
import SwiftUI

/// Text that types itself in when it appears and whenever it changes. Style it like `Text` (`crannyFont`,
/// `foregroundStyle`); pass an already-localized string.
public struct TypewriterText: View {
    /// The text, already localized.
    public var text: String
    /// Typing speed; long strings speed up so typing never takes longer than `maximumDuration`.
    public var charactersPerSecond: Double
    /// Settings ▸ Appearance ▸ Typing effect; false shows the text at once.
    public var animates: Bool
    /// Seconds the typing may take at most.
    public static var maximumDuration: Double { 1.2 }

    @Environment(\.cranny) private var theme
    @State private var progress: Double = 0

    /// Types `text` in at `charactersPerSecond` (default 45) when `animates` (the Typing effect setting) is on.
    public init(_ text: String, charactersPerSecond: Double = 45, animates: Bool = true) {
        self.text = text
        self.charactersPerSecond = charactersPerSecond
        self.animates = animates
    }

    public var body: some View {
        Group {
            if #available(macOS 15.0, *) {
                Text(verbatim: text).textRenderer(TypewriterRenderer(progress: progress))
            } else {
                Text(verbatim: text).opacity(progress > 0 ? 1 : 0)
            }
        }
        .accessibilityLabel(Text(verbatim: text))
        .onAppear { type() }
        .onChange(of: text) { _, _ in type() }
    }

    private func type() {
        guard animates, !theme.reduceMotion, theme.motion != .instant else {
            progress = 1
            return
        }
        progress = 0
        let duration = TypewriterMath.duration(characters: text.count, perSecond: charactersPerSecond,
                                               maximum: Self.maximumDuration)
        if #available(macOS 15.0, *) {
            withAnimation(.linear(duration: duration)) { progress = 1 }   // the glyphs carry the easing
        } else {
            withAnimation(theme.animation(.contentIn)) { progress = 1 }
        }
    }
}

nonisolated enum TypewriterMath {
    /// Glyphs fade in over this many glyph slots, so the front is soft rather than a hard cursor.
    static let softness = 3.0

    static func duration(characters: Int, perSecond: Double, maximum: Double) -> Double {
        min(Double(max(characters, 1)) / max(perSecond, 1), maximum)
    }

    /// Opacity of glyph `index` of `count` at `progress` (0…1).
    static func opacity(index: Int, count: Int, progress: Double) -> Double {
        let front = progress * (Double(count) + softness)
        return Easing.clamped((front - Double(index)) / softness)
    }
}

/// Reveals glyph by glyph with a soft, slightly rising front.
@available(macOS 15.0, *)
struct TypewriterRenderer: TextRenderer, Animatable {
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        let slices = layout.flatMap { line in line.flatMap { run in run.map { $0 } } }
        for (index, slice) in slices.enumerated() {
            let opacity = TypewriterMath.opacity(index: index, count: slices.count, progress: progress)
            guard opacity > 0 else { continue }
            var copy = context
            copy.opacity = opacity
            copy.translateBy(x: 0, y: (1 - opacity) * 2)
            copy.draw(slice)
        }
    }
}

// MARK: - Previews

#Preview("Typewriter") {
    TypewriterText("Drop files on the notch to keep them here")
        .crannyFont(.headline)
        .foregroundStyle(CrannyTheme().palette.label)
        .padding(Space.xl)
        .background(.black)
        .crannyThemeRoot(CrannyTheme())
}

#Preview("Typewriter · Russian") {
    TypewriterText("Перетащите файлы на вырез, чтобы сохранить их здесь")
        .crannyFont(.headline)
        .foregroundStyle(CrannyTheme().palette.label)
        .padding(Space.xl)
        .background(.black)
        .crannyThemeRoot(CrannyTheme())
}
