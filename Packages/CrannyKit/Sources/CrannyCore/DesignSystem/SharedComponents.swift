// CrannyCore/DesignSystem/SharedComponents.swift
// Components added by ARCHITECTURE.md on top of DESIGN.md Appendix A. They read tokens only and take
// ALREADY-LOCALIZED Strings (a LocalizedStringKey passed into Core would be looked up in Bundle.main).
import SwiftUI

// MARK: - Widget states (DESIGN.md §6.8: empty · needs permission · loading · error)

public struct WidgetStateView: View {
    public enum Kind: Sendable { case empty, needsPermission, loading, error }
    @Environment(\.cranny) private var theme
    private let kind: Kind, symbol: String, message: String, actionTitle: String?
    private let action: (@MainActor () -> Void)?

    public init(_ kind: Kind, symbol: String, message: String, actionTitle: String? = nil,
                action: (@MainActor () -> Void)? = nil) {
        self.kind = kind; self.symbol = symbol; self.message = message
        self.actionTitle = actionTitle; self.action = action
    }

    public var body: some View {
        let p = theme.palette
        VStack(spacing: Space.s) {
            if kind == .loading {
                ProgressRing(progress: 0.25, color: p.tertiaryLabel, lineWidth: StrokeWidth.ringCompact)
                    .frame(width: 18, height: 18)
            } else {
                Image(systemName: symbol).font(.system(size: 20, weight: .medium))
                    .foregroundStyle(kind == .error ? p.danger : p.secondaryLabel)
            }
            Text(message).crannyFont(.callout).foregroundStyle(p.secondaryLabel)
                .multilineTextAlignment(.center).lineLimit(2)
            if let actionTitle, let action {
                Button(action: action) { Text(actionTitle) }
                    .buttonStyle(CrannyChipButtonStyle(prominent: kind == .needsPermission))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Chip / capsule button (pipeline chips, Join capsule, presets)

public struct CrannyChipButtonStyle: ButtonStyle {
    public var tint: Color?
    public var prominent: Bool
    public init(tint: Color? = nil, prominent: Bool = false) { self.tint = tint; self.prominent = prominent }
    public func makeBody(configuration: Configuration) -> some View { ChipBody(configuration: configuration, tint: tint, prominent: prominent) }

    struct ChipBody: View {
        @Environment(\.cranny) private var theme
        @Environment(\.isEnabled) private var enabled
        @State private var hovered = false
        let configuration: Configuration, tint: Color?, prominent: Bool
        var body: some View {
            let p = theme.palette
            let fill: Color = prominent ? (tint ?? .white) : (configuration.isPressed ? p.controlPressed : hovered ? p.controlHover : p.control)
            configuration.label
                .crannyFont(.caption).fontWeight(.semibold)
                .foregroundStyle(prominent ? Color.black : (tint ?? p.label))
                .padding(.horizontal, Space.m).frame(minHeight: 22)
                .background(Capsule(style: .continuous).fill(fill))
                .contentShape(Capsule(style: .continuous))
                .opacity(enabled ? 1 : 0.4)
                .onHover { hovered = $0 }
                .animation(theme.animation(.hover), value: hovered)
        }
    }
}

// MARK: - Scrubber (interactive LevelBar: media seek, HUD-style sliders)

public struct Scrubber: View {
    @Environment(\.cranny) private var theme
    @State private var hovered = false
    @State private var dragValue: Double?
    private let value: Double
    private let step: Double
    private let label: String
    private let valueDescription: String
    private let onCommit: @MainActor (Double) -> Void

    /// `value` 0…1. `step` is the VoiceOver/arrow-key increment (e.g. 10 s / duration).
    public init(value: Double, step: Double, label: String, valueDescription: String,
                onCommit: @escaping @MainActor (Double) -> Void) {
        self.value = value; self.step = step; self.label = label
        self.valueDescription = valueDescription; self.onCommit = onCommit
    }

    public var body: some View {
        let active = hovered || dragValue != nil
        GeometryReader { g in
            LevelBar(value: dragValue ?? value, tint: theme.accentColor,
                     thickness: active ? StrokeWidth.scrubberActive : StrokeWidth.scrubber)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { dragValue = min(max($0.location.x / max(g.size.width, 1), 0), 1) }
                    .onEnded { _ in if let v = dragValue { onCommit(v) }; dragValue = nil })
        }
        .frame(height: HitTarget.nook.height)
        .onHover { hovered = $0 }
        .accessibilityElement()
        .accessibilityLabel(Text(label))
        .accessibilityValue(Text(valueDescription))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: onCommit(min(value + step, 1))
            case .decrement: onCommit(max(value - step, 0))
            @unknown default: break
            }
        }
    }
}

// MARK: - Marquee (the ONLY marquee: overflowing track title after a 1.5 s hover, DESIGN.md §2.2)

public struct MarqueeText: View {
    @Environment(\.cranny) private var theme
    @State private var textWidth: CGFloat = 0
    @State private var boxWidth: CGFloat = 0
    @State private var offset: CGFloat = 0
    private let text: String, style: CrannyTextStyle, isActive: Bool

    /// `isActive` = hovered for ≥ 1.5 s (the caller owns the timer). Reduce Motion: never scrolls; tooltip instead.
    public init(_ text: String, style: CrannyTextStyle, isActive: Bool) {
        self.text = text; self.style = style; self.isActive = isActive
    }

    public var body: some View {
        let overflow = max(textWidth - boxWidth, 0)
        Text(text).crannyFont(style).lineLimit(1).fixedSize()
            .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { textWidth = $0 }
            .offset(x: offset)
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)   // min 0: the box takes the proposed width, so overflow > 0
            .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { boxWidth = $0 }
            .clipped()
            .help(text)
            .onChange(of: isActive && overflow > 0 && !theme.reduceMotion) { _, run in
                if run {
                    withAnimation(.linear(duration: Double(overflow) / 30).delay(0.3).repeatForever(autoreverses: true)) { offset = -overflow }
                } else {
                    withAnimation(theme.animation(.contentSwap)) { offset = 0 }
                }
            }
            .accessibilityLabel(Text(text))
    }
}
