// CrannySystemActivities/UI/ActivityViews.swift — building blocks shared by the three activities: band glyphs
// and values (DESIGN.md §9.1), the peek row layout (§9.3) and the small battery rings (§9.2).
import CrannyCore
import SwiftUI

// MARK: - Band (compact wings)

/// One glyph in the band: 13 pt semibold × notch unit (DESIGN.md §14.1).
struct BandSymbol: View {
    @Environment(\.cranny) private var theme
    let name: String
    var color: Color?

    var body: some View {
        Image(systemName: name)
            .font(.system(size: 13 * theme.notchUnit, weight: .semibold))
            .foregroundStyle(color ?? theme.palette.label)
            .contentTransition(theme.reduceMotion ? .identity : .symbolEffect(.replace))
            .accessibilityHidden(true)
    }
}

/// A battery level in the band ("82%"), optionally after a 12-pt battery ring. The `compact` style when it
/// fits the slot; otherwise `compactLabel`, and at last without the locale's space before "%" ("100 %" in
/// Russian is 41 pt, the short slot holds 32). Never truncated, never below 10 pt.
struct BandLevel: View {
    @Environment(\.cranny) private var theme
    let percent: Int
    var color: Color?
    var showsRing = false

    var body: some View {
        let full = SystemCopy.percent(percent)
        ViewThatFits(in: .horizontal) {
            level(full, style: .compact)
            level(full, style: .compactLabel)
            level(SystemCopy.tightPercent(percent), style: .compactLabel)
        }
        .foregroundStyle(color ?? theme.palette.label)
        .accessibilityHidden(true)
    }

    private func level(_ text: String, style: CrannyTextStyle) -> some View {
        HStack(spacing: Space.xs) {
            if showsRing {
                BatteryRing(percent: percent)
                    .frame(width: 12 * theme.notchUnit, height: 12 * theme.notchUnit)
            }
            Text(text)
                .crannyFont(style)
                .lineLimit(1)
                .minimumScaleFactor(0.84)
                .contentTransition(theme.reduceMotion ? .opacity : .numericText(value: Double(percent)))
        }
    }
}

// MARK: - Peek row

/// The 40-pt visual of a peek row (DESIGN.md §9.3): a rounded tile, tinted by the activity's meaning.
struct PeekTile<Content: View>: View {
    @Environment(\.cranny) private var theme
    var tint: Color?
    @ViewBuilder var content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.artPeek, style: .continuous)
        content
            .frame(width: 40, height: 40)
            .background(shape.fill(tint.map { $0.opacity(theme.increaseContrast ? 0.30 : 0.18) } ?? theme.palette.control))
            .accessibilityHidden(true)
    }
}

/// `[visual 40] 12 [title / subtitle] 8 [trailing]`. The NotchUI peek host adds the outer 12-pt insets.
struct PeekRowLayout<Visual: View, Trailing: View>: View {
    @Environment(\.cranny) private var theme
    let title: String
    let subtitle: String?
    var subtitleColor: Color?
    @ViewBuilder var visual: Visual
    @ViewBuilder var trailing: Trailing

    var body: some View {
        let p = theme.palette
        HStack(spacing: 0) {
            visual
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .crannyFont(.headline)
                    .foregroundStyle(p.label)
                if let subtitle {
                    Text(subtitle)
                        .crannyFont(.callout)
                        .foregroundStyle(subtitleColor ?? p.secondaryLabel)
                        .contentTransition(.opacity)
                }
            }
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.leading, Space.l)
            .layoutPriority(1)
            Spacer(minLength: Space.m)
            trailing
        }
        .animation(theme.animation(.contentSwap), value: subtitle)
    }
}

// MARK: - Battery rings

/// A small battery ring: `success`, or `warning` below 20 % (DESIGN.md §9.2). Colour is never alone: the
/// level is always printed next to or inside it.
struct BatteryRing: View {
    @Environment(\.cranny) private var theme
    let percent: Int
    var lineWidth: CGFloat = StrokeWidth.ringCompact

    var body: some View {
        ProgressRing(progress: Double(percent) / 100,
                     color: percent < 20 ? theme.palette.warning : theme.palette.success,
                     lineWidth: lineWidth)
            .animation(theme.animation(.contentSwap), value: percent)
            .accessibilityHidden(true)
    }
}

/// One labelled gauge of the Bluetooth peek row: a ring with the level inside and "Left" / "Right" / "Case" below.
struct BatteryPartGauge: View {
    @Environment(\.cranny) private var theme
    let part: AccessoryPart
    let level: BatteryLevel

    var body: some View {
        let p = theme.palette
        let side = (26 * max(theme.textSize.scale, 1)).rounded()      // "100" in `micro` fits inside at every text size
        VStack(spacing: Space.xxs) {
            ZStack {
                BatteryRing(percent: level.percent)
                Text(level.percent, format: .number)
                    .crannyFont(.micro)
                    .foregroundStyle(p.label)
                    .contentTransition(theme.reduceMotion ? .opacity : .numericText(value: Double(level.percent)))
            }
            .frame(width: side, height: side)
            Text(SystemCopy.label(part))
                .crannyFont(.caption)
                .foregroundStyle(p.tertiaryLabel)
                .lineLimit(1)
                .fixedSize()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: SystemCopy.part(part, SystemCopy.percent(level.percent))))
    }
}

// MARK: - Previews

#Preview("Band levels, tiles and gauges") {
    let theme = CrannyTheme()
    VStack(alignment: .leading, spacing: Space.l) {
        HStack(spacing: Space.l) {
            BandSymbol(name: "bolt.fill", color: theme.palette.success)
            BandLevel(percent: 82).frame(width: 32, alignment: .leading)
            BandLevel(percent: 100).frame(width: 32, alignment: .leading)
            BandLevel(percent: 18, showsRing: true).frame(width: 48, alignment: .leading)
        }
        HStack(spacing: Space.l) {
            PeekTile(tint: theme.palette.success) { BatteryGlyph(percent: 82, fill: theme.palette.success, showsBolt: true) }
            PeekTile { Image(systemName: "headphones").font(.system(size: 18, weight: .medium)) }
            BatteryPartGauge(part: .left, level: BatteryLevel(percent: 84))
            BatteryPartGauge(part: .chargingCase, level: BatteryLevel(percent: 12))
        }
    }
    .padding(Space.xxl)
    .background(.black)
    .crannyThemeRoot(theme)
}
