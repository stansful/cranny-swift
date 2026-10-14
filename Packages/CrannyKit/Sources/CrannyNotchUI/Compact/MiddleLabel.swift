// CrannyNotchUI/Compact/MiddleLabel.swift — the compact middle on displays without a notch: a 12-pt gap, or
// the primary activity's `middleLabel` (`compactLabel`, ≤ 160 pt, e.g. the track title; DESIGN.md §3.5).
// The scene's owner measures the label with `MiddleLabelMetrics` and writes `NotchSceneModel.middleLabelWidth`,
// so the shape (`geometry`) and the wings (`CompactSlots(label:)`) agree on the width (open issue 3).
import AppKit
import CrannyCore
import SwiftUI

/// Width of the compact middle label for `NotchSceneModel.middleLabelWidth`.
public enum MiddleLabelMetrics {
    /// The label never grows beyond this (DESIGN.md §3.5).
    public static let maximumWidth: CGFloat = 160

    /// Width of `label` drawn in `compactLabel` at the display's notch unit, rounded up to whole points and
    /// clamped to 160 pt. 0 when there is no label or the display has a notch (the camera is the middle).
    public static func width(of label: String?, layout: NotchLayout) -> CGFloat {
        guard !layout.metrics.hasNotch, layout.noNotchStyle != .off,
              let label = label?.trimmingCharacters(in: .whitespacesAndNewlines), !label.isEmpty else { return 0 }
        let style = CrannyTextStyle.compactLabel
        let font = font(style, size: style.pointSize(textSize: .standard, notchUnit: layout.u))
        let width = (label as NSString).size(withAttributes: [.font: font, .kern: style.spec.tracking]).width
        return min(width.rounded(.up), maximumWidth)
    }

    /// The AppKit twin of `CrannyTextStyle.font`: the same weight and design, and monospaced digits when the
    /// style has them (`compactLabel` does, so "Track 11" is wider than its proportional-digit measure).
    private static func font(_ style: CrannyTextStyle, size: CGFloat) -> NSFont {
        let spec = style.spec
        let base = NSFont.systemFont(ofSize: size, weight: weight(spec.weight))
        var descriptor = base.fontDescriptor
        if spec.design == .rounded, let rounded = descriptor.withDesign(.rounded) { descriptor = rounded }
        if spec.monoDigits {
            descriptor = descriptor.addingAttributes([.featureSettings: [[
                NSFontDescriptor.FeatureKey.typeIdentifier: kNumberSpacingType,
                NSFontDescriptor.FeatureKey.selectorIdentifier: kMonospacedNumbersSelector,
            ]]])
        }
        return NSFont(descriptor: descriptor, size: size) ?? base
    }

    private static func weight(_ weight: Font.Weight) -> NSFont.Weight {
        switch weight {
        case .ultraLight: .ultraLight
        case .thin: .thin
        case .light: .light
        case .medium: .medium
        case .semibold: .semibold
        case .bold: .bold
        case .heavy: .heavy
        case .black: .black
        default: .regular
        }
    }
}

/// The label itself: one line, secondary, tail-truncated, exactly `width` wide.
struct MiddleLabel: View {
    @Environment(\.cranny) private var theme
    let text: String
    let width: CGFloat

    var body: some View {
        Text(verbatim: text)
            .crannyFont(.compactLabel)
            .foregroundStyle(theme.palette.secondaryLabel)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(width: width)
            .accessibilityHidden(true)            // part of the activity's own label
    }
}

#Preview("Middle label · floating island") {
    let layout = NotchLayout(metrics: NotchMetrics(hasNotch: false, notchWidth: 0, bandHeight: 30, screenWidth: 1920))
    let title = "Midnight Window"
    let width = MiddleLabelMetrics.width(of: title, layout: layout)
    CompactSlots(layout: layout, slot: .short, label: width,
                 leading: { Image(systemName: "music.note").accessibilityHidden(true) },
                 center: { MiddleLabel(text: title, width: width) },
                 trailing: { Image(systemName: "waveform").accessibilityHidden(true) })
        .foregroundStyle(.white)
        .background(Capsule().fill(.black))
        .padding()
        .background(Color(white: 0.2))
        .crannyThemeRoot(CrannyTheme())
}
