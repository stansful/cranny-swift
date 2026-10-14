// CrannyNotchUI/Compact/MiddleLabel.swift — the compact middle on displays without a notch: a 12-pt gap, or
// the primary activity's `middleLabel` (`compactLabel`, ≤ 160 pt, e.g. the track title; DESIGN.md §3.5).
// The scene's owner measures the label with `MiddleLabelMetrics` and writes `NotchSceneModel.middleLabelWidth`,
// so the shape (`geometry`) and the wings (`CompactSlots(label:)`) agree on the width (open issue 3). The owner asks
// again on every media snapshot, mostly for the same title: the last measure is kept.
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
        let unit = layout.u
        if let last, last.label == label, last.unit == unit { return last.width }
        // `BandFont` has monospaced digits like `compactLabel`, so "Track 11" is wider than a proportional measure.
        let width = min(WingTextMetrics.width(of: label, style: .compactLabel, notchUnit: unit), maximumWidth)
        last = (label, unit, width)
        return width
    }

    /// The last label measured, at which notch unit, and its width.
    private static var last: (label: String, unit: CGFloat, width: CGFloat)?
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
