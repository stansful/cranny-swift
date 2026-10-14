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
                Image(systemName: symbol).crannySymbol(.widgetState)
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

/// A 22-pt capsule with a caption-semibold title, in a button of at least `HitTarget.nook` (28 × 24, DESIGN.md §2.3,
/// §16): the capsule is drawn centred in the larger frame, and the whole frame takes clicks. A button's hit area is its
/// own frame, so the room has to be inside the style: a frame or content shape added OUTSIDE a `Button` does not widen
/// it. A row that must stay 22 pt tall takes the extra point back with `.padding(.vertical, -1)` outside the button
/// (that keeps the hit area).
public struct CrannyChipButtonStyle: ButtonStyle {
    /// Height of the drawn capsule.
    public static let height: CGFloat = 22
    /// Foreground (plain chip) or fill (prominent chip); nil = label colour / white.
    public var tint: Color?
    /// A filled chip with dark text: the one primary action of a row.
    public var prominent: Bool
    /// A plain chip, or a prominent one filled with `tint` (white by default).
    public init(tint: Color? = nil, prominent: Bool = false) { self.tint = tint; self.prominent = prominent }
    /// The chip around `configuration.label`.
    public func makeBody(configuration: Configuration) -> some View { ChipBody(configuration: configuration, tint: tint, prominent: prominent) }

    struct ChipBody: View {
        @Environment(\.cranny) private var theme
        @Environment(\.isEnabled) private var enabled
        @State private var hovered = false
        let configuration: Configuration, tint: Color?, prominent: Bool
        var body: some View {
            let p = theme.palette
            let fill: Color = prominent ? (tint ?? p.prominentFill) : (configuration.isPressed ? p.controlPressed : hovered ? p.controlHover : p.control)
            configuration.label
                .crannyFont(.caption).fontWeight(.semibold)
                .foregroundStyle(prominent ? p.onProminent : (tint ?? p.label))
                .padding(.horizontal, Space.m).frame(minHeight: CrannyChipButtonStyle.height)
                .background(Capsule(style: .continuous).fill(fill))
                .frame(minWidth: HitTarget.nook.width, minHeight: HitTarget.nook.height)
                .contentShape(Rectangle())
                .opacity(enabled ? 1 : 0.4)
                .onHover { hovered = $0 }
                .animation(theme.animation(.hover), value: hovered)
        }
    }
}

// MARK: - Text link (an empty state's "Open Music")

/// A text link inside the Nook: caption semibold in `info` (DESIGN.md §2.1: links are `info`; the accent never colours
/// text), underlined while hovered, in a button of at least 28 × 24 that takes clicks over its whole frame. Prefer a
/// chip for a primary action; use this for a secondary way out of an empty state.
public struct CrannyLinkButtonStyle: ButtonStyle {
    /// The link style.
    public init() {}
    /// The link around `configuration.label`.
    public func makeBody(configuration: Configuration) -> some View { LinkBody(configuration: configuration) }

    struct LinkBody: View {
        @Environment(\.cranny) private var theme
        @Environment(\.isEnabled) private var enabled
        @State private var hovered = false
        let configuration: Configuration
        var body: some View {
            configuration.label
                .crannyFont(.caption).fontWeight(.semibold)
                .foregroundStyle(theme.palette.info)
                .underline(hovered)
                .opacity(enabled ? (configuration.isPressed ? 0.7 : 1) : 0.4)
                .frame(minWidth: HitTarget.nook.width, minHeight: HitTarget.nook.height, alignment: .leading)
                .contentShape(Rectangle())
                .onHover { hovered = $0 }
        }
    }
}

// MARK: - Scrubber (interactive LevelBar: media seek, HUD-style sliders)

public struct Scrubber: View {
    @Environment(\.cranny) private var theme
    @Environment(\.layoutDirection) private var direction
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
                    // The location is physical; the bar fills from the leading edge (the right one, right to left).
                    .onChanged { dragValue = direction.fraction(atPhysicalX: $0.location.x, width: g.size.width) }
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

/// One-line text that, while `isActive`, scrolls ONCE to its end and back (30 pt/s, a 0.3-s lead-in and a 1-s pause
/// at the end), then rests. A new hover, a new title or a new width starts another pass; nothing loops, so it costs
/// nothing while the pointer rests on the title (ARCHITECTURE.md §9.2). With Reduce Motion or Motion ▸ Instant it
/// never moves: it truncates with an ellipsis and the tooltip shows the full title. An overflowing text starts where
/// its own first letter puts it and scrolls toward its end: a Latin title in an Arabic layout starts at the left,
/// an Arabic one in an English layout at the right (as the truncated `Text` it replaces shows them).
public struct MarqueeText: View {
    @Environment(\.cranny) private var theme
    @Environment(\.layoutDirection) private var layoutDirection
    @State private var textWidth: CGFloat = 0
    @State private var boxWidth: CGFloat = 0
    @State private var offset: CGFloat = 0
    /// Increments on every start or stop, so the completion of an older pass never moves the text.
    @State private var pass = 0
    private let text: String, style: CrannyTextStyle, isActive: Bool

    /// Scroll speed (pt/s), the pause before a pass starts and the pause at the far end (s).
    public static let speed: CGFloat = 30
    public static let leadIn: Double = 0.3
    public static let dwell: Double = 1

    /// `isActive` = hovered for ≥ 1.5 s (the caller owns the timer).
    public init(_ text: String, style: CrannyTextStyle, isActive: Bool) {
        self.text = text; self.style = style; self.isActive = isActive
    }

    /// Whether the marquee may move at all (not under Reduce Motion or Motion ▸ Instant).
    static func moves(_ theme: CrannyTheme) -> Bool { !theme.reduceMotion && theme.motion != .instant }

    private struct Run: Equatable {
        var active: Bool
        var overflow: CGFloat
        var text: String
    }

    public var body: some View {
        if Self.moves(theme) {
            scrolling
        } else {
            Text(text).crannyFont(style).lineLimit(1).truncationMode(.tail)
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                .help(text)
                .accessibilityLabel(Text(text))
        }
    }

    private var scrolling: some View {
        let overflow = max(textWidth - boxWidth, 0)
        // A text that fits keeps the layout's alignment; one that overflows is laid out in its own direction, so its
        // start shows first and the (mirrored, right to left) offset scrolls toward its end.
        let direction = overflow > 0 ? BidiIsolation.direction(of: text) ?? layoutDirection : layoutDirection
        return Text(text).crannyFont(style).lineLimit(1).fixedSize()
            .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { textWidth = $0 }
            .offset(x: offset)
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)   // min 0: the box takes the proposed width, so overflow > 0
            .environment(\.layoutDirection, direction)
            .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { boxWidth = $0 }
            .clipped()
            .help(text)
            .onChange(of: Run(active: isActive && overflow > 0, overflow: overflow, text: text), initial: true) { _, run in
                play(run)
            }
            .accessibilityLabel(Text(text))
    }

    /// One pass out and back, or back to the start when the run ends.
    private func play(_ run: Run) {
        pass += 1
        let current = pass
        guard run.active else {
            withAnimation(theme.animation(.contentSwap)) { offset = 0 }
            return
        }
        var restart = Transaction()
        restart.disablesAnimations = true
        withTransaction(restart) { offset = 0 }
        let duration = Double(run.overflow / Self.speed)
        withAnimation(.linear(duration: duration).delay(Self.leadIn)) {
            offset = -run.overflow
        } completion: {
            guard current == pass else { return }
            withAnimation(.linear(duration: duration).delay(Self.dwell)) { offset = 0 }
        }
    }
}
