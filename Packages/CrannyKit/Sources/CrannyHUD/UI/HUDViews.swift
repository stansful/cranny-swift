// CrannyHUD/UI/HUDViews.swift — the HUD's anatomy (DESIGN.md §10): left of the camera an optional value and
// a 13-pt semibold glyph hugging the camera; right of it a 64u × 6 `LevelBar` on a `control` track. After the
// first press only the bar (`hudLevel`) and the digits (`.numericText`) move; the shape never does. Pressing
// past 0 % or 100 % nudges the bar 2 pt and springs it back (`snapBack`, no overshoot under Calm / Reduce Motion).
import CrannyCore
import SwiftUI

/// Module-local sizes from DESIGN.md §10 that have no shared token (× notch unit in the band).
nonisolated enum HUDMetrics {
    /// The level bar in the band: 64u (the `wide` slot's 72-pt content budget minus air).
    static let barLength: CGFloat = 64
    /// The level bar in a peek row.
    static let peekBarLength: CGFloat = 120
    /// The glyph well in a peek row (DESIGN.md §9.3: visual 40 × 40, r 10).
    static let peekVisual: CGFloat = 40
}

/// Which palette colour fills the bar (Settings ▸ HUD ▸ Colors, DESIGN.md §10). Pure.
nonisolated enum HUDTint: Equatable, Sendable {
    case white, accent, caution, info

    init(_ colors: HUDColors, kind: HUDKind) {
        switch (colors, kind) {
        case (.mono, _): self = .white
        case (.accent, _), (.semantic, .volume): self = .accent
        case (.semantic, .brightness): self = .caution
        case (.semantic, .keyboardBacklight): self = .info
        }
    }

    /// nil = the bar's default fill (`label`, white).
    func color(in theme: CrannyTheme) -> Color? {
        switch self {
        case .white: nil
        case .accent: theme.accentColor
        case .caution: theme.palette.caution
        case .info: theme.palette.info
        }
    }
}

// MARK: - Glyph

/// The kind's glyph: `speaker.wave.3.fill` with the level as variable value, `speaker.slash.fill` when muted,
/// `sun.*` / `light.*` for brightness and the keyboard, or the output device's glyph with one `.bounce`
/// (`HUDDisplay.symbolName`: mute always wins).
struct HUDGlyph: View {
    @Environment(\.cranny) private var theme
    let activity: HUDActivity
    var style: CrannyTextStyle = .compact

    var body: some View {
        if let display = activity.display {
            let symbol = display.symbolName
            let variable = display.symbolVariableValue
            Image(systemName: symbol, variableValue: variable)
                .symbolRenderingMode(variable == nil ? .monochrome : .hierarchical)   // unfilled waves dim; the rest white
                .crannyFont(style)
                .foregroundStyle(theme.palette.label)
                .contentTransition(theme.symbolReplace)
                .modifier(GlyphBounce(value: display.glyphBounce))
                .animation(theme.animation(.contentSwap), value: symbol)
                .accessibilityHidden(true)
        }
    }
}

/// One `.bounce` per increment of `value` (a new output device, DESIGN.md §10). None under Reduce Motion or the
/// Instant personality (§4.2: "no animation at all"). The effect is left out rather than fed a constant, so turning
/// either setting off later does not look like an increment and bounce a glyph that did not change.
private struct GlyphBounce: ViewModifier {
    @Environment(\.cranny) private var theme
    let value: Int

    func body(content: Content) -> some View {
        if theme.reduceMotion || theme.motion == .instant {
            content
        } else {
            content.symbolEffect(.bounce, options: .nonRepeating, value: value)
        }
    }
}

// MARK: - Compact (band) presentation

/// Leading wing: [value] [glyph] — the glyph hugs the camera (`CompactSlots` aligns this side trailing).
struct HUDLeadingView: View {
    @Environment(\.cranny) private var theme
    let activity: HUDActivity

    var body: some View {
        if let display = activity.display {
            HStack(spacing: Space.xs * theme.notchUnit) {
                if activity.settings[HUDSettings.showsValue] || theme.differentiateWithoutColor {
                    Text(display.percent, format: .number)
                        .crannyFont(.compactLabel)
                        .foregroundStyle(display.isMuted ? theme.palette.tertiaryLabel : theme.palette.secondaryLabel)
                        .contentTransition(.numericText(value: Double(display.percent)))
                        .animation(theme.animation(.hudLevel), value: display.percent)
                        .lineLimit(1)
                        .fixedSize()
                }
                HUDGlyph(activity: activity)
            }
            .accessibilityHidden(true)
        }
    }
}

/// Trailing wing: the level bar, white by default, `tertiaryLabel` when muted, 16 ticks for fine steps
/// (and always under Differentiate Without Color / Increase Contrast, drawn by `LevelBar`).
struct HUDTrailingView: View {
    @Environment(\.cranny) private var theme
    let activity: HUDActivity
    var length: CGFloat = HUDMetrics.barLength

    var body: some View {
        if let display = activity.display {
            let tint = HUDTint(activity.settings[HUDSettings.colors], kind: display.kind)
            LevelBar(value: display.level, tint: tint.color(in: theme), steps: LevelStepper.steps,
                     showsTicks: display.showsFineTicks, muted: display.isMuted)
                .frame(width: length * theme.notchUnit)
                .modifier(LimitBump(edge: display.bumpEdge, serial: display.bumpSerial))
                .accessibilityHidden(true)
        }
    }
}

/// The 2-pt rubber band when a press pushes against 0 % or 100 % (DESIGN.md §4.3, §5.5 "HUD at a limit").
private struct LimitBump: ViewModifier {
    @Environment(\.cranny) private var theme
    let edge: LevelEdge
    let serial: Int

    func body(content: Content) -> some View {
        if theme.motion == .instant {
            content                                        // Instant: no animation at all (DESIGN.md §4.2)
        } else {
            let push = (edge == .top ? 1 : -1) * GestureSpec.limitBump
            let reduceMotion = theme.reduceMotion
            let out = Self.spring(.hudLevel, bounceScale: 0)
            let back = Self.spring(.snapBack, bounceScale: reduceMotion ? 0 : theme.motion.bounceScale)
            content.keyframeAnimator(initialValue: CGFloat.zero, trigger: serial) { view, offset in
                view.offset(x: offset)
            } keyframes: { _ in
                KeyframeTrack {
                    if reduceMotion {
                        MoveKeyframe(push)
                        CubicKeyframe(0, duration: back.duration)
                    } else {
                        SpringKeyframe(push, duration: out.duration, spring: out)
                        SpringKeyframe(0, duration: back.duration, spring: back)
                    }
                }
            }
        }
    }

    /// A motion token's spring: out with `hudLevel` (critically damped), back with `snapBack` (bounce × Motion,
    /// capped like `CrannyMotion`; none under Calm or Reduce Motion, so the bump lands without overshoot).
    private static func spring(_ kind: CrannyMotion.Kind, bounceScale: Double) -> Spring {
        guard case .spring(let duration, let bounce) = CrannyMotion.spec(kind).curve else { return Spring() }
        return Spring(duration: duration, bounce: min(bounce * bounceScale, 0.35))
    }
}

// MARK: - Peek row and preview helper

/// Peek anatomy (DESIGN.md §9.3): [glyph 40] [title / value] … [bar]. The HUD rarely peeks (it is P0 and
/// transient); this row exists for hover peeks that list every visible activity.
struct HUDPeekRow: View {
    @Environment(\.cranny) private var theme
    let activity: HUDActivity

    var body: some View {
        if let display = activity.display {
            HStack(spacing: Space.l) {
                HUDGlyph(activity: activity, style: .title)
                    .frame(width: HUDMetrics.peekVisual, height: HUDMetrics.peekVisual)
                    .background(RoundedRectangle(cornerRadius: Radius.artPeek, style: .continuous).fill(theme.palette.control))
                VStack(alignment: .leading, spacing: Space.xxs) {
                    Text(verbatim: display.kind.title).crannyFont(.headline).foregroundStyle(theme.palette.label)
                    Text(verbatim: HUDCopy.accessibilityValue(display)).crannyFont(.callout).foregroundStyle(theme.palette.secondaryLabel)
                }
                .lineLimit(1)
                Spacer(minLength: Space.m)
                HUDTrailingView(activity: activity, length: HUDMetrics.peekBarLength)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: display.kind.title))
            .accessibilityValue(Text(verbatim: HUDCopy.accessibilityValue(display)))
        }
    }
}

// MARK: - Previews

#Preview("HUD · volume, 14″ notch") {
    HUDBandPreview(activity: previewHUD(HUDDisplay(kind: .volume, level: 0.62)))
}

#Preview("HUD · value, semantic brightness") {
    HUDBandPreview(activity: previewHUD(HUDDisplay(kind: .brightness, level: 0.75)) {
        $0[HUDSettings.showsValue] = true
        $0[HUDSettings.colors] = .semantic
    })
}

#Preview("HUD · muted, fine ticks") {
    HUDBandPreview(activity: previewHUD(HUDDisplay(kind: .volume, level: 0.4, isMuted: true, showsFineTicks: true)))
}

#Preview("HUD · keyboard, floating island") {
    HUDBandPreview(activity: previewHUD(HUDDisplay(kind: .keyboardBacklight, level: 0.25)),
                   metrics: NotchMetrics(hasNotch: false, notchWidth: 0, bandHeight: 30, screenWidth: 1920))
}

#Preview("HUD · peek row") {
    HUDPeekRow(activity: previewHUD(HUDDisplay(kind: .volume, level: 0.62)))
        .frame(width: 400, height: NotchLayout.peekRow)
        .padding(.horizontal, Space.l)
        .background(.black)
        .crannyThemeRoot(CrannyTheme())
}
