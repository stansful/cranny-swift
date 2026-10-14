// CrannyOnboarding/Tutorial/TipBubbleView.swift — the tip under the real notch (DESIGN.md §12.2): a dark
// `.regularMaterial` bubble whose caret points at the shape, one sentence, a `KeyCap` where relevant, "2 of 5"
// in `micro` and an always-visible "Skip tour". Opaque under Reduce Transparency; ✓ bounces once when a step
// is really done (not under Reduce Motion). It belongs to the notch family, so it is always dark.
import CrannyCore
import Observation
import SwiftUI

/// What the hosting panel shows; updating it re-renders the bubble in place.
@MainActor @Observable final class TipModel {
    var content: TipContent
    @ObservationIgnored var onAction: @MainActor () -> Void = {}
    init(content: TipContent) { self.content = content }
}

struct TipBubbleView: View {
    let model: TipModel

    var body: some View {
        TipBubble(content: model.content, onAction: { model.onAction() })
            .padding(TipBubble.shadowMargin)
            .crannyThemeRoot(CrannyTheme())
    }
}

struct TipBubble: View {
    @Environment(\.cranny) private var theme
    @Environment(\.displayScale) private var displayScale
    let content: TipContent
    let onAction: () -> Void

    /// Room around the bubble for its shadow (the panel is transparent there and passes clicks through).
    static let shadowMargin = Space.xxl
    static let caretSize = CGSize(width: Space.l + Space.xs, height: Space.s)
    static let maximumWidth: CGFloat = 340

    var body: some View {
        let shape = BubbleShape(radius: Radius.peek - Space.s, caret: Self.caretSize)
        VStack(alignment: .leading, spacing: Space.m) {
            HStack(alignment: .firstTextBaseline, spacing: Space.m) {
                mark
                Text(verbatim: content.text)
                    .crannyFont(.headline)
                    .foregroundStyle(theme.palette.label)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let keys = content.keys { KeyCap(keys) }
            }
            if content.progress != nil || content.actionTitle != nil {
                HStack(spacing: Space.m) {
                    if let progress = content.progress {
                        Text(verbatim: progress).crannyFont(.micro).foregroundStyle(theme.palette.tertiaryLabel)
                    }
                    Spacer(minLength: Space.l)
                    if let title = content.actionTitle {
                        Button(action: onAction) {
                            Text(verbatim: title).crannyFont(.caption).foregroundStyle(theme.palette.secondaryLabel)
                                .padding(.horizontal, Space.m)
                                .frame(minHeight: HitTarget.nook.height)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .background(Capsule(style: .continuous).fill(theme.palette.control))
                    }
                }
            }
        }
        .padding(.horizontal, Space.l + Space.xxs)
        .padding(.top, Space.l + Self.caretSize.height)
        .padding(.bottom, Space.l)
        .frame(maxWidth: Self.maximumWidth, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .background { background(shape) }
        .overlay(shape.stroke(theme.palette.hairline, lineWidth: theme.increaseContrast ? 1 : StrokeWidth.hairline(displayScale)))
        .crannyElevation(Elevation.peek)
        .environment(\.colorScheme, .dark)
        .animation(theme.animation(.contentSwap), value: content)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(verbatim: content.text))
    }

    @ViewBuilder private var mark: some View {
        switch content.mark {
        case .none:
            EmptyView()
        case .symbol(let symbol):
            Image(systemName: symbol)
                .font(.system(size: CrannyTextStyle.headline.spec.size, weight: .semibold))
                .foregroundStyle(theme.accentColor)
                .accessibilityHidden(true)
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: CrannyTextStyle.headline.spec.size, weight: .semibold))
                .foregroundStyle(theme.palette.success)
                .symbolEffect(.bounce, value: content.mark == .done && !theme.reduceMotion)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder private func background(_ shape: BubbleShape) -> some View {
        if theme.reduceTransparency {
            ZStack { shape.fill(theme.palette.surface); shape.fill(theme.palette.card) }
        } else {
            shape.fill(.regularMaterial)
        }
    }
}

/// A rounded rectangle with a caret centred on its top edge, as one outline (one material, one stroke).
nonisolated struct BubbleShape: Shape {
    let radius: CGFloat
    let caret: CGSize

    func path(in rect: CGRect) -> Path {
        let body = CGRect(x: rect.minX, y: rect.minY + caret.height, width: rect.width, height: rect.height - caret.height)
        var path = RoundedRectangle(cornerRadius: radius, style: .continuous).path(in: body)
        var tip = Path()
        tip.move(to: CGPoint(x: rect.midX - caret.width / 2, y: body.minY + 0.5))
        tip.addQuadCurve(to: CGPoint(x: rect.midX, y: rect.minY), control: CGPoint(x: rect.midX - caret.width / 6, y: body.minY))
        tip.addQuadCurve(to: CGPoint(x: rect.midX + caret.width / 2, y: body.minY + 0.5), control: CGPoint(x: rect.midX + caret.width / 6, y: body.minY))
        tip.closeSubpath()
        path = path.union(tip)
        return path
    }
}

#Preview("Tip · waiting, done, coach") {
    VStack(spacing: Space.l) {
        TipBubble(content: TipContent(text: "Hold ⌘ to see every shortcut", keys: "⌘", progress: "4 of 5",
                                      mark: .symbol("keyboard"), actionTitle: "Skip tour"), onAction: {})
        TipBubble(content: TipContent(text: "Drag any file onto the notch", progress: "2 of 5", mark: .done,
                                      actionTitle: "Skip tour"), onAction: {})
        TipBubble(content: TipContent(text: "Rest the pointer here, or press", keys: "⌃⌥N"), onAction: {})
    }
    .padding(Space.huge)
    .background(BrandColor.graphite.color)
    .crannyThemeRoot(CrannyTheme())
}
